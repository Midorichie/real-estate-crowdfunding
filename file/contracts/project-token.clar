;; contracts/project-token.clar

;; Import NFT trait
(use-trait nft-trait .nft-trait.nft-trait)

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-authorized (err u101))
(define-constant err-invalid-token-uri (err u102))
(define-constant err-token-exists (err u103))
(define-constant err-invalid-project (err u104))
(define-constant err-invalid-shares (err u105))
(define-constant err-invalid-recipient (err u106))
(define-constant err-token-not-found (err u107))

;; Implement NFT trait
(impl-trait .nft-trait.nft-trait)

;; Storage
(define-non-fungible-token project-token uint)

(define-map token-uris
    uint
    { uri: (string-utf8 256) }
)

(define-map project-tokens
    uint
    {
        owner: principal,
        project-id: uint,
        shares: uint
    }
)

;; Token counter
(define-data-var token-id-nonce uint u0)

;; Only crowdfunding contract can call certain functions
(define-constant crowdfunding-contract 'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM.crowdfunding)

;; Check if caller is crowdfunding contract
(define-private (is-crowdfunding-contract)
    (is-eq contract-caller crowdfunding-contract)
)

;; Required by NFT trait
(define-public (get-last-token-id)
    (ok (var-get token-id-nonce))
)

;; Validate project ID (simplified validation)
(define-private (is-valid-project-id (project-id uint))
    (< project-id u1000000) ;; Example maximum project ID
)

;; Validate shares amount
(define-private (is-valid-shares (shares uint))
    (and 
        (> shares u0)
        (<= shares u1000000) ;; Maximum shares limit
    )
)

;; Validate token URI
(define-private (is-valid-token-uri (uri (string-utf8 256)))
    (> (len uri) u0)
)

;; Mint new token with added validation
(define-public (mint (recipient principal) (project-id uint) (shares uint) (token-uri (string-utf8 256)))
    (let
        (
            (token-id (var-get token-id-nonce))
        )
        ;; Authorization check
        (asserts! (is-crowdfunding-contract) err-not-authorized)
        ;; Token existence check
        (asserts! (is-none (map-get? token-uris token-id)) err-token-exists)
        ;; Recipient validation
        (asserts! (not (is-eq recipient (as-contract tx-sender))) err-invalid-recipient)
        ;; Project ID validation
        (asserts! (is-valid-project-id project-id) err-invalid-project)
        ;; Shares validation
        (asserts! (is-valid-shares shares) err-invalid-shares)
        ;; Token URI validation
        (asserts! (is-valid-token-uri token-uri) err-invalid-token-uri)
        
        ;; Mint token
        (try! (nft-mint? project-token token-id recipient))
        ;; Store token URI
        (map-set token-uris token-id { uri: token-uri })
        ;; Store token details
        (map-set project-tokens token-id
            {
                owner: recipient,
                project-id: project-id,
                shares: shares
            }
        )
        ;; Increment token counter
        (var-set token-id-nonce (+ token-id u1))
        (ok token-id)
    )
)

;; Get token URI
(define-public (get-token-uri (token-id uint))
    (ok (some (get uri (unwrap! (map-get? token-uris token-id) err-invalid-token-uri))))
)

;; Get token owner
(define-public (get-owner (token-id uint))
    (ok (nft-get-owner? project-token token-id))
)

;; Get token details
(define-read-only (get-token-details (token-id uint))
    (ok (map-get? project-tokens token-id))
)

;; Transfer token with added validation
(define-public (transfer (token-id uint) (sender principal) (recipient principal))
    (begin
        ;; Authorization check
        (asserts! (is-eq tx-sender sender) err-not-authorized)
        ;; Recipient validation
        (asserts! (not (is-eq recipient (as-contract tx-sender))) err-invalid-recipient)
        ;; Token existence check
        (asserts! (is-some (nft-get-owner? project-token token-id)) err-token-not-found)
        ;; Ownership check
        (asserts! (is-eq (some sender) (nft-get-owner? project-token token-id)) err-not-authorized)
        
        (nft-transfer? project-token token-id sender recipient)
    )
)
