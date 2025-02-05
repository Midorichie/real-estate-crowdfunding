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

;; Data Variables
(define-map Projects
    { project-id: uint }
    {
        owner: principal,
        target-amount: uint,
        current-amount: uint,
        status: (string-ascii 20),
        milestone-count: uint
    }
)

(define-map Milestones
    { project-id: uint, milestone-id: uint }
    {
        description: (string-ascii 256),
        amount: uint,
        status: (string-ascii 20)
    }
)

(define-map Contributions
    { project-id: uint, contributor: principal }
    { amount: uint }
)

;; Project counter for generating unique IDs
(define-data-var project-counter uint u0)

;; Private Functions

;; Validate project ID
(define-private (is-valid-project-id (project-id uint)) 
    (and 
        (< project-id (var-get project-counter))
        (is-some (map-get? Projects { project-id: project-id }))
    )
)

;; Public Functions

;; Create new project
(define-public (create-project (target-amount uint) (milestone-count uint))
    (let
        (
            (project-id (var-get project-counter))
        )
        (asserts! (> target-amount u0) err-invalid-amount)
        (asserts! (> milestone-count u0) err-invalid-amount)
        (asserts! (map-insert Projects
            { project-id: project-id }
            {
                owner: tx-sender,
                target-amount: target-amount,
                current-amount: u0,
                status: "active",
                milestone-count: milestone-count
            }
        ) err-project-exists)
        (var-set project-counter (+ project-id u1))
        (ok project-id)
    )
)

;; Contribute to project
(define-public (contribute (project-id uint))
    (begin
        ;; Validate project ID first
        (asserts! (is-valid-project-id project-id) err-invalid-project-id)
        (let
            (
                (project (unwrap! (map-get? Projects { project-id: project-id }) err-project-not-found))
                (contribution-amount (stx-get-balance tx-sender))
            )
            (asserts! (> contribution-amount u0) err-invalid-amount)
            (try! (stx-transfer? contribution-amount tx-sender (as-contract tx-sender)))
            
            ;; Update project current amount
            (map-set Projects
                { project-id: project-id }
                (merge project { current-amount: (+ (get current-amount project) contribution-amount) })
            )
            
            ;; Record contribution
            (map-set Contributions
                { project-id: project-id, contributor: tx-sender }
                { amount: contribution-amount }
            )
            
            (ok true)
        )
    )
)

;; Read-only functions

;; Get project details
(define-read-only (get-project (project-id uint))
    (begin
        (asserts! (is-valid-project-id project-id) err-invalid-project-id)
        (ok (unwrap! (map-get? Projects { project-id: project-id }) err-project-not-found))
    )
)

;; Get contribution amount
(define-read-only (get-contribution (project-id uint) (contributor principal))
    (begin
        (asserts! (is-valid-project-id project-id) err-invalid-project-id)
        (ok (unwrap! (map-get? Contributions 
            { project-id: project-id, contributor: contributor }
        ) err-project-not-found))
    )
)
