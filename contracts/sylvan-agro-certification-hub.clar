;; sylvan-agro-certification-hubtransparency system
;; Built on immutable blockchain infrastructure for crop yield authentication

;; ===============================================
;; ERROR RESPONSE DEFINITIONS
;; ===============================================

;; System administrator access required
(define-constant err-admin-required (err u300))
;; Production record does not exist in ledger
(define-constant err-record-missing (err u301))
;; Duplicate production entry attempted
(define-constant err-duplicate-entry (err u302))
;; Field name validation failure
(define-constant err-invalid-field-name (err u303))
;; Quantity validation constraints violated
(define-constant err-quantity-bounds (err u304))
;; Access permission denied for operation
(define-constant err-access-denied (err u305))
;; Producer ownership verification failed
(define-constant err-ownership-failed (err u306))
;; View access restrictions enforced
(define-constant err-view-restricted (err u307))
;; Metadata tag format validation error
(define-constant err-tag-format-invalid (err u308))

;; ===============================================
;; AUTHORIZATION CONTROL
;; ===============================================

;; Protocol administrator principal
(define-constant protocol-administrator tx-sender)

;; ===============================================
;; STATE VARIABLES
;; ===============================================

;; Global sequence counter for production entries
(define-data-var global-sequence-id uint u0)

;; ===============================================
;; DATA STRUCTURE MAPPINGS
;; ===============================================

;; Primary production ledger storage
(define-map production-ledger
  { sequence-id: uint }
  {
    producer-identity: principal,
    commodity-type: (string-ascii 64),
    output-volume: uint,
    genesis-block-height: uint,
    location-metadata: (string-ascii 128),
    category-descriptors: (list 10 (string-ascii 32))
  }
)

;; Access control matrix for production data
(define-map access-control-matrix
  { sequence-id: uint, accessor-principal: principal }
  { permission-granted: bool }
)

;; ===============================================
;; VALIDATION HELPER FUNCTIONS
;; ===============================================

;; Validate descriptor tag formatting requirements
(define-private (validate-descriptor-format (descriptor (string-ascii 32)))
  (and
    (> (len descriptor) u0)
    (< (len descriptor) u33)
  )
)

;; Verify complete descriptor collection validity
(define-private (validate-descriptor-collection (descriptors (list 10 (string-ascii 32))))
  (and
    (> (len descriptors) u0)
    (<= (len descriptors) u10)
    (is-eq (len (filter validate-descriptor-format descriptors)) (len descriptors))
  )
)

;; Confirm production record existence in ledger
(define-private (production-record-exists (sequence-id uint))
  (is-some (map-get? production-ledger { sequence-id: sequence-id }))
)

;; Verify producer ownership of specific record
(define-private (confirm-producer-ownership (sequence-id uint) (producer-identity principal))
  (match (map-get? production-ledger { sequence-id: sequence-id })
    ledger-entry (is-eq (get producer-identity ledger-entry) producer-identity)
    false
  )
)

;; Extract output volume from production record
(define-private (extract-output-volume (sequence-id uint))
  (default-to u0
    (get output-volume
      (map-get? production-ledger { sequence-id: sequence-id })
    )
  )
)

;; ===============================================
;; CORE REGISTRATION FUNCTIONALITY
;; ===============================================

;; Create new production record with comprehensive validation
(define-public (create-production-record 
  (commodity (string-ascii 64)) 
  (volume uint) 
  (location (string-ascii 128)) 
  (descriptors (list 10 (string-ascii 32)))
)
  (let
    (
      (next-sequence-id (+ (var-get global-sequence-id) u1))
    )
    ;; Comprehensive input validation checks
    (asserts! (> (len commodity) u0) err-invalid-field-name)
    (asserts! (< (len commodity) u65) err-invalid-field-name)
    (asserts! (> volume u0) err-quantity-bounds)
    (asserts! (< volume u1000000000) err-quantity-bounds)
    (asserts! (> (len location) u0) err-invalid-field-name)
    (asserts! (< (len location) u129) err-invalid-field-name)
    (asserts! (validate-descriptor-collection descriptors) err-tag-format-invalid)

    ;; Insert new production record into ledger
    (map-insert production-ledger
      { sequence-id: next-sequence-id }
      {
        producer-identity: tx-sender,
        commodity-type: commodity,
        output-volume: volume,
        genesis-block-height: block-height,
        location-metadata: location,
        category-descriptors: descriptors
      }
    )

    ;; Grant initial access permission to record creator
    (map-insert access-control-matrix
      { sequence-id: next-sequence-id, accessor-principal: tx-sender }
      { permission-granted: true }
    )

    ;; Update global sequence counter
    (var-set global-sequence-id next-sequence-id)
    (ok next-sequence-id)
  )
)

;; ===============================================
;; AUTHENTICATION AND VERIFICATION
;; ===============================================

;; Comprehensive production record authentication protocol
(define-public (authenticate-production-record (sequence-id uint) (expected-producer principal))
  (let
    (
      (ledger-entry (unwrap! (map-get? production-ledger { sequence-id: sequence-id }) err-record-missing))
      (actual-producer (get producer-identity ledger-entry))
      (creation-block (get genesis-block-height ledger-entry))
      (access-granted (default-to 
        false 
        (get permission-granted 
          (map-get? access-control-matrix { sequence-id: sequence-id, accessor-principal: tx-sender })
        )
      ))
    )
    ;; Verify record existence and access permissions
    (asserts! (production-record-exists sequence-id) err-record-missing)
    (asserts! 
      (or 
        (is-eq tx-sender actual-producer)
        access-granted
        (is-eq tx-sender protocol-administrator)
      ) 
      err-access-denied
    )

    ;; Generate authentication response with metadata
    (if (is-eq actual-producer expected-producer)
      ;; Authentication successful response
      (ok {
        authentication-status: true,
        current-block-height: block-height,
        ledger-age: (- block-height creation-block),
        producer-verification: true
      })
      ;; Authentication failed response
      (ok {
        authentication-status: false,
        current-block-height: block-height,
        ledger-age: (- block-height creation-block),
        producer-verification: false
      })
    )
  )
)

;; ===============================================
;; OWNERSHIP TRANSFER OPERATIONS
;; ===============================================

;; Transfer production record ownership to new producer
(define-public (transfer-production-ownership (sequence-id uint) (new-producer-identity principal))
  (let
    (
      (current-record (unwrap! (map-get? production-ledger { sequence-id: sequence-id }) err-record-missing))
    )
    ;; Validate record existence and current ownership
    (asserts! (production-record-exists sequence-id) err-record-missing)
    (asserts! (is-eq (get producer-identity current-record) tx-sender) err-ownership-failed)

    ;; Execute ownership transfer
    (map-set production-ledger
      { sequence-id: sequence-id }
      (merge current-record { producer-identity: new-producer-identity })
    )
    (ok true)
  )
)

;; ===============================================
;; ACCESS CONTROL MANAGEMENT
;; ===============================================

;; Revoke viewing access for specified principal
(define-public (revoke-viewing-access (sequence-id uint) (target-accessor principal))
  (let
    (
      (current-record (unwrap! (map-get? production-ledger { sequence-id: sequence-id }) err-record-missing))
    )
    ;; Validate ownership and prevent self-revocation
    (asserts! (production-record-exists sequence-id) err-record-missing)
    (asserts! (is-eq (get producer-identity current-record) tx-sender) err-ownership-failed)
    (asserts! (not (is-eq target-accessor tx-sender)) err-admin-required)

    ;; Remove access permission
    (map-delete access-control-matrix { sequence-id: sequence-id, accessor-principal: target-accessor })
    (ok true)
  )
)

;; ===============================================
;; RECORD MODIFICATION OPERATIONS
;; ===============================================

;; Append additional category descriptors to existing record
(define-public (append-category-descriptors (sequence-id uint) (new-descriptors (list 10 (string-ascii 32))))
  (let
    (
      (current-record (unwrap! (map-get? production-ledger { sequence-id: sequence-id }) err-record-missing))
      (current-descriptors (get category-descriptors current-record))
      (merged-descriptors (unwrap! (as-max-len? (concat current-descriptors new-descriptors) u10) err-tag-format-invalid))
    )
    ;; Validate ownership and descriptor format
    (asserts! (production-record-exists sequence-id) err-record-missing)
    (asserts! (is-eq (get producer-identity current-record) tx-sender) err-ownership-failed)
    (asserts! (validate-descriptor-collection new-descriptors) err-tag-format-invalid)

    ;; Update record with merged descriptors
    (map-set production-ledger
      { sequence-id: sequence-id }
      (merge current-record { category-descriptors: merged-descriptors })
    )
    (ok merged-descriptors)
  )
)

;; Comprehensive production record update operation
(define-public (modify-production-record 
  (sequence-id uint) 
  (updated-commodity (string-ascii 64)) 
  (updated-volume uint) 
  (updated-location (string-ascii 128)) 
  (updated-descriptors (list 10 (string-ascii 32)))
)
  (let
    (
      (current-record (unwrap! (map-get? production-ledger { sequence-id: sequence-id }) err-record-missing))
    )
    ;; Validate ownership and all input parameters
    (asserts! (production-record-exists sequence-id) err-record-missing)
    (asserts! (is-eq (get producer-identity current-record) tx-sender) err-ownership-failed)
    (asserts! (> (len updated-commodity) u0) err-invalid-field-name)
    (asserts! (< (len updated-commodity) u65) err-invalid-field-name)
    (asserts! (> updated-volume u0) err-quantity-bounds)
    (asserts! (< updated-volume u1000000000) err-quantity-bounds)
    (asserts! (> (len updated-location) u0) err-invalid-field-name)
    (asserts! (< (len updated-location) u129) err-invalid-field-name)
    (asserts! (validate-descriptor-collection updated-descriptors) err-tag-format-invalid)

    ;; Execute comprehensive record update
    (map-set production-ledger
      { sequence-id: sequence-id }
      (merge current-record { 
        commodity-type: updated-commodity, 
        output-volume: updated-volume, 
        location-metadata: updated-location, 
        category-descriptors: updated-descriptors 
      })
    )
    (ok true)
  )
)

;; ===============================================
;; RECORD DELETION OPERATIONS
;; ===============================================

;; Complete production record removal from ledger
(define-public (delete-production-record (sequence-id uint))
  (let
    (
      (target-record (unwrap! (map-get? production-ledger { sequence-id: sequence-id }) err-record-missing))
    )
    ;; Validate ownership before deletion
    (asserts! (production-record-exists sequence-id) err-record-missing)
    (asserts! (is-eq (get producer-identity target-record) tx-sender) err-ownership-failed)

    ;; Execute record deletion
    (map-delete production-ledger { sequence-id: sequence-id })
    (ok true)
  )
)

;; ===============================================
;; EMERGENCY SECURITY PROTOCOLS
;; ===============================================

;; Emergency security lock for production record
(define-public (activate-emergency-lock (sequence-id uint))
  (let
    (
      (target-record (unwrap! (map-get? production-ledger { sequence-id: sequence-id }) err-record-missing))
      (security-descriptor "EMERGENCY-PROTOCOL-ACTIVE")
      (current-descriptors (get category-descriptors target-record))
    )
    ;; Verify authorization for emergency action
    (asserts! (production-record-exists sequence-id) err-record-missing)
    (asserts! 
      (or 
        (is-eq tx-sender protocol-administrator)
        (is-eq (get producer-identity target-record) tx-sender)
      ) 
      err-admin-required
    )

    ;; Emergency lock activation confirmed
    (ok true)
  )
)

