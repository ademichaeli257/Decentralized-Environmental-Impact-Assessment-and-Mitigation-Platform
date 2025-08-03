;; Construction Project Environmental Review Contract
;; Evaluates potential environmental impacts of development projects

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-PROJECT-NOT-FOUND (err u101))
(define-constant ERR-INVALID-INPUT (err u102))
(define-constant ERR-PROJECT-ALREADY-EXISTS (err u103))
(define-constant ERR-INSUFFICIENT-PAYMENT (err u104))

;; Data Variables
(define-data-var next-project-id uint u1)
(define-data-var review-fee uint u1000000) ;; 1 STX in microSTX
(define-data-var contract-paused bool false)

;; Data Maps
(define-map projects uint {
  owner: principal,
  location: {x: uint, y: uint},
  project-type: (string-ascii 50),
  size: uint,
  status: (string-ascii 20),
  environmental-score: uint,
  mitigation-required: uint,
  created-at: uint,
  reviewed-at: (optional uint),
  reviewer: (optional principal)
})

(define-map project-details uint {
  description: (string-ascii 500),
  estimated-duration: uint,
  expected-emissions: uint,
  water-usage: uint,
  waste-generation: uint,
  noise-level: uint
})

(define-map authorized-reviewers principal bool)

;; Authorization Functions
(define-private (is-contract-owner)
  (is-eq tx-sender CONTRACT-OWNER))

(define-private (is-authorized-reviewer)
  (default-to false (map-get? authorized-reviewers tx-sender)))

;; Administrative Functions
(define-public (add-reviewer (reviewer principal))
  (begin
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
    (ok (map-set authorized-reviewers reviewer true))))

(define-public (remove-reviewer (reviewer principal))
  (begin
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
    (ok (map-delete authorized-reviewers reviewer))))

(define-public (set-review-fee (new-fee uint))
  (begin
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
    (ok (var-set review-fee new-fee))))

(define-public (toggle-contract-pause)
  (begin
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
    (ok (var-set contract-paused (not (var-get contract-paused))))))

;; Core Functions
(define-public (submit-project
  (location {x: uint, y: uint})
  (project-type (string-ascii 50))
  (size uint)
  (description (string-ascii 500))
  (estimated-duration uint)
  (expected-emissions uint)
  (water-usage uint)
  (waste-generation uint)
  (noise-level uint))
  (let ((project-id (var-get next-project-id)))
    (begin
      (asserts! (not (var-get contract-paused)) ERR-NOT-AUTHORIZED)
      (asserts! (> size u0) ERR-INVALID-INPUT)
      (asserts! (> estimated-duration u0) ERR-INVALID-INPUT)
      (asserts! (>= (stx-get-balance tx-sender) (var-get review-fee)) ERR-INSUFFICIENT-PAYMENT)

      ;; Transfer review fee
      (try! (stx-transfer? (var-get review-fee) tx-sender CONTRACT-OWNER))

      ;; Store project data
      (map-set projects project-id {
        owner: tx-sender,
        location: location,
        project-type: project-type,
        size: size,
        status: "submitted",
        environmental-score: u0,
        mitigation-required: u0,
        created-at: block-height,
        reviewed-at: none,
        reviewer: none
      })

      ;; Store project details
      (map-set project-details project-id {
        description: description,
        estimated-duration: estimated-duration,
        expected-emissions: expected-emissions,
        water-usage: water-usage,
        waste-generation: waste-generation,
        noise-level: noise-level
      })

      (var-set next-project-id (+ project-id u1))
      (ok project-id))))

(define-public (review-project
  (project-id uint)
  (environmental-score uint)
  (mitigation-required uint)
  (approval-status (string-ascii 20)))
  (let ((project (unwrap! (map-get? projects project-id) ERR-PROJECT-NOT-FOUND)))
    (begin
      (asserts! (is-authorized-reviewer) ERR-NOT-AUTHORIZED)
      (asserts! (is-eq (get status project) "submitted") ERR-INVALID-INPUT)
      (asserts! (<= environmental-score u100) ERR-INVALID-INPUT)
      (asserts! (or (is-eq approval-status "approved")
                    (is-eq approval-status "rejected")
                    (is-eq approval-status "conditional")) ERR-INVALID-INPUT)

      (ok (map-set projects project-id (merge project {
        status: approval-status,
        environmental-score: environmental-score,
        mitigation-required: mitigation-required,
        reviewed-at: (some block-height),
        reviewer: (some tx-sender)
      }))))))

(define-public (update-project-status
  (project-id uint)
  (new-status (string-ascii 20)))
  (let ((project (unwrap! (map-get? projects project-id) ERR-PROJECT-NOT-FOUND)))
    (begin
      (asserts! (or (is-eq tx-sender (get owner project)) (is-authorized-reviewer)) ERR-NOT-AUTHORIZED)
      (ok (map-set projects project-id (merge project {status: new-status}))))))

;; Read-only Functions
(define-read-only (get-project (project-id uint))
  (map-get? projects project-id))

(define-read-only (get-project-details (project-id uint))
  (map-get? project-details project-id))

(define-read-only (get-next-project-id)
  (var-get next-project-id))

(define-read-only (get-review-fee)
  (var-get review-fee))

(define-read-only (is-reviewer (address principal))
  (default-to false (map-get? authorized-reviewers address)))

(define-read-only (calculate-environmental-impact
  (size uint)
  (emissions uint)
  (water-usage uint)
  (waste-generation uint)
  (noise-level uint))
  (let ((base-impact (/ (* size u10) u1000))
        (emission-impact (/ emissions u100))
        (water-impact (/ water-usage u1000))
        (waste-impact (/ waste-generation u50))
        (noise-impact (if (> noise-level u70) u20 u0)))
    (+ base-impact emission-impact water-impact waste-impact noise-impact)))

(define-read-only (get-projects-by-status (status (string-ascii 20)))
  (ok status)) ;; Simplified for this implementation

(define-read-only (is-contract-paused)
  (var-get contract-paused))
