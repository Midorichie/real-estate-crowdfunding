;; contracts/project-token.clar

;; Import NFT trait
(use-trait nft-trait .nft-trait.nft-trait)

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-authorized (err u101))
(define-constant err-invalid-token-uri (err u102))
(define-constant err-token-exists (err u103))

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
(define-constant crowdfunding-contract .crowdfunding)

;; Check if caller is crowdfunding contract
(define-private (is-crowdfunding-contract)
    (is-eq contract-caller crowdfunding-contract)
)

;; Required by NFT trait
(define-public (get-last-token-id)
    (ok (var-get token-id-nonce))
)

;; Mint new token
(define-public (mint (recipient principal) (project-id uint) (shares uint) (token-uri (string-utf8 256)))
    (let
        (
            (token-id (var-get token-id-nonce))
        )
        (asserts! (is-crowdfunding-contract) err-not-authorized)
        (asserts! (is-none (map-get? token-uris token-id)) err-token-exists)
        
        (try! (nft-mint? project-token token-id recipient))
        (map-set token-uris token-id { uri: token-uri })
        (map-set project-tokens token-id
            {
                owner: recipient,
                project-id: project-id,
                shares: shares
            }
        )
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

;; Transfer token
(define-public (transfer (token-id uint) (sender principal) (recipient principal))
    (begin
        (asserts! (is-eq tx-sender sender) err-not-authorized)
        (nft-transfer? project-token token-id sender recipient)
    )
)
