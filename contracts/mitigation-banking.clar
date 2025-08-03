;; Environmental Mitigation Banking Contract
;; Manages habitat restoration projects that offset development impacts

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u500))
(define-constant ERR-BANK-NOT-FOUND (err u501))
(define-constant ERR-INSUFFICIENT-CREDITS (err u502))
(define-constant ERR-INVALID-INPUT (err u503))
(define-constant ERR-INSUFFICIENT-PAYMENT (err u504))
(define-constant ERR-BANK-NOT-ACTIVE (err u505))

;; Data Variables
(define-data-var next-bank-id uint u1)
(define-data-var next-transaction-id uint u1)
(define-data-var contract-paused bool false)
(define-data-var platform-fee-percentage uint u5) ;; 5% platform fee

;; Data Maps
(define-map mitigation-banks uint {
  name: (string-ascii 100),
  location: {x: uint, y: uint},
  habitat-type: (string-ascii 50),
  total-credits: uint,
  available-credits: uint,
  credit-price: uint, ;; Price per credit in microSTX
  restoration-status: (string-ascii 20),
  operator: principal,
  created-at: uint,
  active: bool
})

(define-map bank-details uint {
  description: (string-ascii 500),
  restoration-area-hectares: uint,
  target-species: (list 10 (string-ascii 50)),
  restoration-timeline: uint, ;; months
  monitoring-period: uint, ;; months
  success-criteria: (string-ascii 200),
  regulatory-approval: bool
})

(define-map credit-transactions uint {
  bank-id: uint,
  buyer: principal,
  seller: principal,
  credits-transferred: uint,
  price-per-credit: uint,
  total-amount: uint,
  transaction-type: (string-ascii 20), ;; purchase, transfer, retirement
  project-id: (optional uint),
  timestamp: uint
})

(define-map user-credit-balances {user: principal, bank-id: uint} uint)

(define-map authorized-operators principal bool)

;; Authorization Functions
(define-private (is-contract-owner)
  (is-eq tx-sender CONTRACT-OWNER))

(define-private (is-authorized-operator)
  (default-to false (map-get? authorized-operators tx-sender)))

(define-private (is-bank-operator (bank-id uint))
  (match (map-get? mitigation-banks bank-id)
    bank (is-eq tx-sender (get operator bank))
    false))

;; Administrative Functions
(define-public (add-operator (operator principal))
  (begin
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
    (ok (map-set authorized-operators operator true))))

(define-public (remove-operator (operator principal))
  (begin
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
    (ok (map-delete authorized-operators operator))))

(define-public (set-platform-fee (new-fee-percentage uint))
  (begin
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
    (asserts! (<= new-fee-percentage u20) ERR-INVALID-INPUT) ;; Max 20% fee
    (ok (var-set platform-fee-percentage new-fee-percentage))))

(define-public (toggle-contract-pause)
  (begin
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
    (ok (var-set contract-paused (not (var-get contract-paused))))))

;; Core Functions
(define-public (create-mitigation-bank
  (name (string-ascii 100))
  (location {x: uint, y: uint})
  (habitat-type (string-ascii 50))
  (total-credits uint)
  (credit-price uint)
  (description (string-ascii 500))
  (restoration-area-hectares uint)
  (target-species (list 10 (string-ascii 50)))
  (restoration-timeline uint)
  (monitoring-period uint)
  (success-criteria (string-ascii 200)))
  (let ((bank-id (var-get next-bank-id)))
    (begin
      (asserts! (is-authorized-operator) ERR-NOT-AUTHORIZED)
      (asserts! (not (var-get contract-paused)) ERR-NOT-AUTHORIZED)
      (asserts! (> total-credits u0) ERR-INVALID-INPUT)
      (asserts! (> credit-price u0) ERR-INVALID-INPUT)
      (asserts! (> restoration-area-hectares u0) ERR-INVALID-INPUT)
      (asserts! (> restoration-timeline u0) ERR-INVALID-INPUT)

      ;; Create mitigation bank
      (map-set mitigation-banks bank-id {
        name: name,
        location: location,
        habitat-type: habitat-type,
        total-credits: total-credits,
        available-credits: total-credits,
        credit-price: credit-price,
        restoration-status: "planning",
        operator: tx-sender,
        created-at: block-height,
        active: true
      })

      ;; Store bank details
      (map-set bank-details bank-id {
        description: description,
        restoration-area-hectares: restoration-area-hectares,
        target-species: target-species,
        restoration-timeline: restoration-timeline,
        monitoring-period: monitoring-period,
        success-criteria: success-criteria,
        regulatory-approval: false
      })

      (var-set next-bank-id (+ bank-id u1))
      (ok bank-id))))

(define-public (purchase-credits
  (bank-id uint)
  (credits-requested uint))
  (let ((bank (unwrap! (map-get? mitigation-banks bank-id) ERR-BANK-NOT-FOUND))
        (total-cost (* credits-requested (get credit-price bank)))
        (platform-fee (/ (* total-cost (var-get platform-fee-percentage)) u100))
        (seller-amount (- total-cost platform-fee))
        (transaction-id (var-get next-transaction-id)))
    (begin
      (asserts! (get active bank) ERR-BANK-NOT-ACTIVE)
      (asserts! (>= (get available-credits bank) credits-requested) ERR-INSUFFICIENT-CREDITS)
      (asserts! (>= (stx-get-balance tx-sender) total-cost) ERR-INSUFFICIENT-PAYMENT)

      ;; Transfer payment to bank operator
      (try! (stx-transfer? seller-amount tx-sender (get operator bank)))

      ;; Transfer platform fee to contract owner
      (try! (stx-transfer? platform-fee tx-sender CONTRACT-OWNER))

      ;; Update bank credits
      (map-set mitigation-banks bank-id (merge bank {
        available-credits: (- (get available-credits bank) credits-requested)
      }))

      ;; Update buyer's credit balance
      (let ((current-balance (default-to u0 (map-get? user-credit-balances {user: tx-sender, bank-id: bank-id}))))
        (map-set user-credit-balances {user: tx-sender, bank-id: bank-id} (+ current-balance credits-requested)))

      ;; Record transaction
      (map-set credit-transactions transaction-id {
        bank-id: bank-id,
        buyer: tx-sender,
        seller: (get operator bank),
        credits-transferred: credits-requested,
        price-per-credit: (get credit-price bank),
        total-amount: total-cost,
        transaction-type: "purchase",
        project-id: none,
        timestamp: block-height
      })

      (var-set next-transaction-id (+ transaction-id u1))
      (ok transaction-id))))

(define-public (retire-credits
  (bank-id uint)
  (credits-to-retire uint)
  (project-id uint))
  (let ((current-balance (default-to u0 (map-get? user-credit-balances {user: tx-sender, bank-id: bank-id})))
        (transaction-id (var-get next-transaction-id)))
    (begin
      (asserts! (>= current-balance credits-to-retire) ERR-INSUFFICIENT-CREDITS)

      ;; Update user's credit balance
      (map-set user-credit-balances {user: tx-sender, bank-id: bank-id} (- current-balance credits-to-retire))

      ;; Record retirement transaction
      (map-set credit-transactions transaction-id {
        bank-id: bank-id,
        buyer: tx-sender,
        seller: tx-sender,
        credits-transferred: credits-to-retire,
        price-per-credit: u0,
        total-amount: u0,
        transaction-type: "retirement",
        project-id: (some project-id),
        timestamp: block-height
      })

      (var-set next-transaction-id (+ transaction-id u1))
      (ok transaction-id))))

(define-public (transfer-credits
  (bank-id uint)
  (recipient principal)
  (credits-to-transfer uint))
  (let ((sender-balance (default-to u0 (map-get? user-credit-balances {user: tx-sender, bank-id: bank-id})))
        (recipient-balance (default-to u0 (map-get? user-credit-balances {user: recipient, bank-id: bank-id})))
        (transaction-id (var-get next-transaction-id)))
    (begin
      (asserts! (>= sender-balance credits-to-transfer) ERR-INSUFFICIENT-CREDITS)

      ;; Update balances
      (map-set user-credit-balances {user: tx-sender, bank-id: bank-id} (- sender-balance credits-to-transfer))
      (map-set user-credit-balances {user: recipient, bank-id: bank-id} (+ recipient-balance credits-to-transfer))

      ;; Record transfer transaction
      (map-set credit-transactions transaction-id {
        bank-id: bank-id,
        buyer: recipient,
        seller: tx-sender,
        credits-transferred: credits-to-transfer,
        price-per-credit: u0,
        total-amount: u0,
        transaction-type: "transfer",
        project-id: none,
        timestamp: block-height
      })

      (var-set next-transaction-id (+ transaction-id u1))
      (ok transaction-id))))

(define-public (update-restoration-status
  (bank-id uint)
  (new-status (string-ascii 20)))
  (let ((bank (unwrap! (map-get? mitigation-banks bank-id) ERR-BANK-NOT-FOUND)))
    (begin
      (asserts! (is-bank-operator bank-id) ERR-NOT-AUTHORIZED)
      (asserts! (or (is-eq new-status "planning")
                    (is-eq new-status "in-progress")
                    (is-eq new-status "completed")
                    (is-eq new-status "monitoring")) ERR-INVALID-INPUT)

      (ok (map-set mitigation-banks bank-id (merge bank {restoration-status: new-status}))))))

(define-public (set-regulatory-approval
  (bank-id uint)
  (approved bool))
  (let ((details (unwrap! (map-get? bank-details bank-id) ERR-BANK-NOT-FOUND)))
    (begin
      (asserts! (is-authorized-operator) ERR-NOT-AUTHORIZED)
      (ok (map-set bank-details bank-id (merge details {regulatory-approval: approved}))))))

(define-public (update-credit-price
  (bank-id uint)
  (new-price uint))
  (let ((bank (unwrap! (map-get? mitigation-banks bank-id) ERR-BANK-NOT-FOUND)))
    (begin
      (asserts! (is-bank-operator bank-id) ERR-NOT-AUTHORIZED)
      (asserts! (> new-price u0) ERR-INVALID-INPUT)
      (ok (map-set mitigation-banks bank-id (merge bank {credit-price: new-price}))))))

;; Read-only Functions
(define-read-only (get-mitigation-bank (bank-id uint))
  (map-get? mitigation-banks bank-id))

(define-read-only (get-bank-details (bank-id uint))
  (map-get? bank-details bank-id))

(define-read-only (get-credit-balance (user principal) (bank-id uint))
  (default-to u0 (map-get? user-credit-balances {user: user, bank-id: bank-id})))

(define-read-only (get-transaction (transaction-id uint))
  (map-get? credit-transactions transaction-id))

(define-read-only (get-next-bank-id)
  (var-get next-bank-id))

(define-read-only (get-next-transaction-id)
  (var-get next-transaction-id))

(define-read-only (is-operator (address principal))
  (default-to false (map-get? authorized-operators address)))

(define-read-only (calculate-purchase-cost (bank-id uint) (credits uint))
  (match (map-get? mitigation-banks bank-id)
    bank (let ((total-cost (* credits (get credit-price bank)))
               (platform-fee (/ (* total-cost (var-get platform-fee-percentage)) u100)))
           (ok {total-cost: total-cost, platform-fee: platform-fee, seller-amount: (- total-cost platform-fee)}))
    (err ERR-BANK-NOT-FOUND)))

(define-read-only (get-platform-fee-percentage)
  (var-get platform-fee-percentage))

(define-read-only (is-contract-paused)
  (var-get contract-paused))

(define-read-only (get-available-credits-by-habitat (habitat-type (string-ascii 50)))
  (ok u0)) ;; Simplified implementation

(define-read-only (calculate-mitigation-requirement
  (impact-type (string-ascii 50))
  (impact-area uint)
  (impact-severity uint))
  (let ((base-requirement (* impact-area u2)) ;; 2:1 ratio base
        (severity-multiplier (if (> impact-severity u3) u3 u2)))
    (* base-requirement severity-multiplier)))
