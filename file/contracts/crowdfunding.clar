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
(define-constant minimum-contribution u1000000) ;; 1 STX minimum

;; Data Variables
(define-data-var contract-initialized bool false)
(define-data-var contract-paused bool false)
(define-data-var project-counter uint u0)

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

;; Create new project with deadline
(define-public (create-project (target-amount uint) (milestone-count uint) (duration-days uint))
    (let
        (
            (project-id (var-get project-counter))
            (deadline (+ block-height (* duration-days u144))) ;; ~144 blocks per day
        )
        (asserts! (not (var-get contract-paused)) err-not-active)
        (asserts! (> target-amount minimum-contribution) err-invalid-amount)
        (asserts! (> milestone-count u0) err-invalid-amount)
        (asserts! (>= duration-days u1) err-invalid-amount)
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
        (var-set project-counter (+ project-id u1))
        (ok project-id)
    )
)

;; Contribute to project with rate limiting
(define-public (contribute (project-id uint))
    (begin
        (asserts! (not (var-get contract-paused)) err-not-active)
        (asserts! (is-valid-active-project project-id) err-invalid-project-id)
        (let
            (
                (project (unwrap! (map-get? Projects { project-id: project-id }) err-project-not-found))
                (contribution-amount (stx-get-balance tx-sender))
            )
            (asserts! (>= contribution-amount minimum-contribution) err-invalid-amount)
            (asserts! (<= block-height (get deadline project)) err-not-active)
            (try! (stx-transfer? contribution-amount tx-sender (as-contract tx-sender)))
            
            (map-set Projects
                { project-id: project-id }
                (merge project { current-amount: (+ (get current-amount project) contribution-amount) })
            )
            
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

;; Request refund if deadline passed and target not met
(define-public (request-refund (project-id uint))
    (begin
        (asserts! (is-valid-active-project project-id) err-invalid-project-id)
        (let
            (
                (project (unwrap! (map-get? Projects { project-id: project-id }) err-project-not-found))
                (contribution (unwrap! (map-get? Contributions 
                    { project-id: project-id, contributor: tx-sender }
                ) err-project-not-found))
            )
            (asserts! (> (get deadline project) block-height) err-not-active)
            (asserts! (< (get current-amount project) (get target-amount project)) err-unauthorized)
            (asserts! (not (get refunded contribution)) err-unauthorized)
            
            (try! (as-contract (stx-transfer? (get amount contribution) tx-sender tx-sender)))
            
            (map-set Contributions
                { project-id: project-id, contributor: tx-sender }
                (merge contribution { refunded: true })
            )
            
            (ok true)
        )
    )
)
