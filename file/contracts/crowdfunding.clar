;; contracts/crowdfunding.clar

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-invalid-amount (err u101))
(define-constant err-project-exists (err u102))
(define-constant err-project-not-found (err u103))
(define-constant err-milestone-not-found (err u104))
(define-constant err-insufficient-funds (err u105))
(define-constant err-invalid-project-id (err u106))
(define-constant err-unauthorized (err u107))
(define-constant err-already-initialized (err u108))
(define-constant err-not-active (err u109))
(define-constant err-invalid-duration (err u110))
(define-constant err-invalid-milestone-count (err u111))
(define-constant err-deadline-passed (err u112))
(define-constant err-project-funded (err u113))
(define-constant err-no-contribution (err u114))
(define-constant err-already-refunded (err u115))
(define-constant err-invalid-status (err u116))

(define-constant minimum-contribution u1000000) ;; 1 STX minimum
(define-constant maximum-duration-days u365) ;; 1 year maximum
(define-constant maximum-milestone-count u12) ;; Maximum 12 milestones

;; Data Variables
(define-data-var contract-initialized bool false)
(define-data-var contract-paused bool false)
(define-data-var project-counter uint u0)

;; Validate project status
(define-private (is-valid-status (status (string-ascii 20)))
    (or 
        (is-eq status "active")
        (is-eq status "funded")
        (is-eq status "completed")
        (is-eq status "cancelled")
    )
)

(define-map Projects
    { project-id: uint }
    {
        owner: principal,
        target-amount: uint,
        current-amount: uint,
        status: (string-ascii 20),
        milestone-count: uint,
        created-at: uint,
        deadline: uint
    }
)

(define-map Milestones
    { project-id: uint, milestone-id: uint }
    {
        description: (string-ascii 256),
        amount: uint,
        status: (string-ascii 20),
        approvals: uint
    }
)

(define-map Contributions
    { project-id: uint, contributor: principal }
    { 
        amount: uint,
        timestamp: uint,
        refunded: bool
    }
)

;; Private Functions

;; Authorization check
(define-private (is-contract-owner)
    (is-eq tx-sender contract-owner)
)

;; Validate duration
(define-private (is-valid-duration (duration-days uint))
    (and 
        (>= duration-days u1)
        (<= duration-days maximum-duration-days)
    )
)

;; Validate milestone count
(define-private (is-valid-milestone-count (count uint))
    (and 
        (> count u0)
        (<= count maximum-milestone-count)
    )
)

;; Validate amount
(define-private (is-valid-amount (amount uint))
    (>= amount minimum-contribution)
)

;; Validate milestone - FIXED VERSION
(define-private (is-valid-milestone (project-id uint) (milestone-id uint) (description (string-ascii 256)))
    (match (map-get? Projects { project-id: project-id })
        project (and
            (< milestone-id (get milestone-count project))
            (> (len description) u0)
            (is-none (map-get? Milestones { project-id: project-id, milestone-id: milestone-id }))
        )
        false
    )
)

;; Public Functions

;; Get project counter - needed for NFT contract
(define-read-only (get-project-counter)
    (ok (var-get project-counter))
)

;; Initialize contract
(define-public (initialize)
    (begin
        (asserts! (is-contract-owner) err-owner-only)
        (asserts! (not (var-get contract-initialized)) err-already-initialized)
        (var-set contract-initialized true)
        (ok true)
    )
)

;; Emergency pause
(define-public (set-pause (paused bool))
    (begin
        (asserts! (is-contract-owner) err-owner-only)
        (var-set contract-paused paused)
        (ok true)
    )
)

;; Validate project ID and status
(define-private (is-valid-active-project (project-id uint)) 
    (match (map-get? Projects { project-id: project-id })
        project (and 
            (< project-id (var-get project-counter))
            (is-eq (get status project) "active")
        )
        false
    )
)

;; Create new project with enhanced validation
(define-public (create-project (target-amount uint) (milestone-count uint) (duration-days uint))
    (let
        (
            (project-id (var-get project-counter))
            (deadline (+ block-height (* duration-days u144))) ;; ~144 blocks per day
        )
        ;; Contract state validation
        (asserts! (not (var-get contract-paused)) err-not-active)
        (asserts! (var-get contract-initialized) err-not-active)
        
        ;; Input validation
        (asserts! (is-valid-amount target-amount) err-invalid-amount)
        (asserts! (is-valid-milestone-count milestone-count) err-invalid-milestone-count)
        (asserts! (is-valid-duration duration-days) err-invalid-duration)
        
        ;; Create project
        (asserts! (map-insert Projects
            { project-id: project-id }
            {
                owner: tx-sender,
                target-amount: target-amount,
                current-amount: u0,
                status: "active",
                milestone-count: milestone-count,
                created-at: block-height,
                deadline: deadline
            }
        ) err-project-exists)
        
        ;; Increment project counter
        (var-set project-counter (+ project-id u1))
        (ok project-id)
    )
)

;; Get project details
(define-read-only (get-project (project-id uint))
    (ok (unwrap! (map-get? Projects { project-id: project-id }) err-project-not-found))
)

;; Get contribution details
(define-read-only (get-contribution (project-id uint) (contributor principal))
    (ok (unwrap! (map-get? Contributions { project-id: project-id, contributor: contributor }) err-no-contribution))
)

;; Contribute to project with enhanced validation
(define-public (contribute (project-id uint))
    (begin
        ;; Contract state validation
        (asserts! (not (var-get contract-paused)) err-not-active)
        (asserts! (is-valid-active-project project-id) err-invalid-project-id)
        
        (let
            (
                (project (unwrap! (map-get? Projects { project-id: project-id }) err-project-not-found))
                (contribution-amount (stx-get-balance tx-sender))
                (new-total (+ (get current-amount project) contribution-amount))
            )
            ;; Contribution validation
            (asserts! (>= contribution-amount minimum-contribution) err-invalid-amount)
            (asserts! (<= block-height (get deadline project)) err-deadline-passed)
            
            ;; Process contribution
            (try! (stx-transfer? contribution-amount tx-sender (as-contract tx-sender)))
            
            ;; Update project
            (map-set Projects
                { project-id: project-id }
                (merge project 
                    { 
                        current-amount: new-total,
                        status: (if (>= new-total (get target-amount project)) 
                                  "funded" 
                                  (get status project))
                    }
                )
            )
            
            ;; Record contribution
            (map-set Contributions
                { project-id: project-id, contributor: tx-sender }
                { 
                    amount: contribution-amount,
                    timestamp: block-height,
                    refunded: false
                }
            )
            
            (ok true)
        )
    )
)

;; Request refund with enhanced validation
(define-public (request-refund (project-id uint))
    (begin
        ;; Project validation
        (asserts! (is-valid-active-project project-id) err-invalid-project-id)
        
        (let
            (
                (project (unwrap! (map-get? Projects { project-id: project-id }) err-project-not-found))
                (contribution (unwrap! (map-get? Contributions 
                    { project-id: project-id, contributor: tx-sender }
                ) err-no-contribution))
            )
            ;; Refund conditions validation
            (asserts! (> (get deadline project) block-height) err-deadline-passed)
            (asserts! (< (get current-amount project) (get target-amount project)) err-project-funded)
            (asserts! (not (get refunded contribution)) err-already-refunded)
            
            ;; Process refund
            (try! (as-contract (stx-transfer? (get amount contribution) tx-sender tx-sender)))
            
            ;; Update contribution record
            (map-set Contributions
                { project-id: project-id, contributor: tx-sender }
                (merge contribution { refunded: true })
            )
            
            ;; Update project amount
            (map-set Projects
                { project-id: project-id }
                (merge project 
                    { current-amount: (- (get current-amount project) (get amount contribution)) }
                )
            )
            
            (ok true)
        )
    )
)

;; Add milestone
(define-public (add-milestone (project-id uint) (milestone-id uint) (description (string-ascii 256)) (amount uint))
    (begin
        (let
            (
                (project (unwrap! (map-get? Projects { project-id: project-id }) err-project-not-found))
            )
            ;; Validation
            (asserts! (is-eq (get owner project) tx-sender) err-unauthorized)
            (asserts! (is-valid-milestone project-id milestone-id description) err-invalid-project-id)
            (asserts! (is-valid-amount amount) err-invalid-amount)
            
            ;; Create milestone
            (map-set Milestones
                { project-id: project-id, milestone-id: milestone-id }
                {
                    description: description,
                    amount: amount,
                    status: "pending",
                    approvals: u0
                }
            )
            
            (ok true)
        )
    )
)

;; Get milestone details
(define-read-only (get-milestone (project-id uint) (milestone-id uint))
    (ok (unwrap! (map-get? Milestones { project-id: project-id, milestone-id: milestone-id }) err-milestone-not-found))
)
