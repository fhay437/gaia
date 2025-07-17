;; Gaia Impact Tracking Smart Contract
;; A decentralized platform for tracking, verifying, and rewarding environmental actions
;; Built on Stacks blockchain for transparency and immutability

;; Constants
(define-constant VAULT-GUARDIAN tx-sender)
(define-constant ERR-UNAUTHORIZED-ACCESS (err u100))
(define-constant ERR-INVALID-MISSION (err u101))
(define-constant ERR-MISSION-ALREADY-VERIFIED (err u102))
(define-constant ERR-MISSION-NOT-FOUND (err u103))
(define-constant ERR-INVALID-REWARD-AMOUNT (err u104))
(define-constant ERR-INVALID-PARAMETERS (err u105))

;; Data Variables
(define-data-var total-missions uint u0)
(define-data-var global-impact-points uint u0)

;; Define mission blueprints map for valid environmental actions
(define-map mission-blueprints 
    { mission-type: (string-ascii 32) }
    { 
        base-impact: uint,
        difficulty-multiplier: uint,
        is-active: bool
    }
)

;; Define environmental missions map
(define-map environmental-missions
    { mission-id: uint }
    {
        guardian: principal,
        mission-type: (string-ascii 32),
        coordinates: (string-ascii 64),
        completion-time: uint,
        impact-points: uint,
        proof-data: (string-utf8 256),
        is-verified: bool,
        validator: (optional principal)
    }
)

;; Define guardian profiles map
(define-map guardian-profiles
    principal
    {
        completed-missions: uint,
        total-impact-points: uint,
        eco-reputation: uint
    }
)

;; Read-only functions

(define-read-only (get-mission-details (mission-id uint))
    (map-get? environmental-missions { mission-id: mission-id })
)

(define-read-only (get-guardian-profile (guardian principal))
    (default-to 
        { completed-missions: u0, total-impact-points: u0, eco-reputation: u0 }
        (map-get? guardian-profiles guardian)
    )
)

(define-read-only (get-mission-blueprint (mission-type (string-ascii 32)))
    (map-get? mission-blueprints { mission-type: mission-type })
)

(define-read-only (get-global-impact)
    (var-get global-impact-points)
)

;; Internal helper functions

(define-private (calculate-mission-impact (mission-type (string-ascii 32)))
    (let (
        (blueprint-info (unwrap! (map-get? mission-blueprints { mission-type: mission-type }) u0))
    )
    (* (get base-impact blueprint-info) (get difficulty-multiplier blueprint-info)))
)

(define-private (update-guardian-profile (guardian principal) (impact-points uint))
    (let (
        (current-profile (get-guardian-profile guardian))
    )
    (map-set guardian-profiles 
        guardian
        {
            completed-missions: (+ (get completed-missions current-profile) u1),
            total-impact-points: (+ (get total-impact-points current-profile) impact-points),
            eco-reputation: (+ (get eco-reputation current-profile) u1)
        }
    ))
)

;; Public functions

(define-public (register-mission-blueprint 
    (mission-type (string-ascii 32)) 
    (base-impact uint)
    (difficulty-multiplier uint)
)
    (begin
        (asserts! (is-eq tx-sender VAULT-GUARDIAN) ERR-UNAUTHORIZED-ACCESS)
        (asserts! (> (len mission-type) u0) ERR-INVALID-PARAMETERS)
        (asserts! (> base-impact u0) ERR-INVALID-PARAMETERS)
        (asserts! (> difficulty-multiplier u0) ERR-INVALID-PARAMETERS)
        (ok (map-set mission-blueprints
            { mission-type: mission-type }
            {
                base-impact: base-impact,
                difficulty-multiplier: difficulty-multiplier,
                is-active: true
            }
        ))
    )
)

(define-public (deactivate-mission-blueprint (mission-type (string-ascii 32)))
    (begin 
        (asserts! (is-eq tx-sender VAULT-GUARDIAN) ERR-UNAUTHORIZED-ACCESS)
        (asserts! (> (len mission-type) u0) ERR-INVALID-PARAMETERS)
        (let (
            (existing-blueprint (unwrap! (map-get? mission-blueprints { mission-type: mission-type }) ERR-INVALID-MISSION))
        )
        (begin
            (asserts! (get is-active existing-blueprint) ERR-INVALID-MISSION)
            (ok (map-set mission-blueprints
                { mission-type: mission-type }
                (merge existing-blueprint { is-active: false })
            ))
        ))
    )
)

(define-public (submit-environmental-mission
    (mission-type (string-ascii 32))
    (coordinates (string-ascii 64))
    (proof-data (string-utf8 256))
)
    (let (
        (mission-id (var-get total-missions))
        (blueprint-info (unwrap! (map-get? mission-blueprints { mission-type: mission-type }) ERR-INVALID-MISSION))
    )
    (begin
        (asserts! (get is-active blueprint-info) ERR-INVALID-MISSION)
        (asserts! (> (len mission-type) u0) ERR-INVALID-PARAMETERS)
        (asserts! (> (len coordinates) u0) ERR-INVALID-PARAMETERS)
        (asserts! (> (len proof-data) u0) ERR-INVALID-PARAMETERS)
        (let (
            (impact-points (calculate-mission-impact mission-type))
        )
        (begin
            (map-set environmental-missions
                { mission-id: mission-id }
                {
                    guardian: tx-sender,
                    mission-type: mission-type,
                    coordinates: coordinates,
                    completion-time: block-height,
                    impact-points: impact-points,
                    proof-data: proof-data,
                    is-verified: false,
                    validator: none
                }
            )
            (var-set total-missions (+ mission-id u1))
            (ok mission-id)
        )))
    )
)

(define-public (verify-mission (mission-id uint))
    (begin
        (asserts! (is-eq tx-sender VAULT-GUARDIAN) ERR-UNAUTHORIZED-ACCESS)
        (asserts! (<= mission-id (var-get total-missions)) ERR-MISSION-NOT-FOUND)
        (let (
            (mission-data (unwrap! (map-get? environmental-missions { mission-id: mission-id }) ERR-MISSION-NOT-FOUND))
        )
        (begin
            (asserts! (not (get is-verified mission-data)) ERR-MISSION-ALREADY-VERIFIED)
            (let (
                (verified-mission (merge mission-data { 
                    is-verified: true,
                    validator: (some tx-sender)
                }))
            )
            (begin
                (map-set environmental-missions { mission-id: mission-id } verified-mission)
                (var-set global-impact-points (+ (var-get global-impact-points) (get impact-points mission-data)))
                (update-guardian-profile (get guardian mission-data) (get impact-points mission-data))
                (ok true)
            ))
        ))
    )
)

;; Initialize supported mission types
(begin
    (try! (register-mission-blueprint "FOREST_RESTORATION" u10 u2))
    (try! (register-mission-blueprint "CARBON_CAPTURE" u15 u2))
    (try! (register-mission-blueprint "OCEAN_CLEANUP" u5 u1))
    (try! (register-mission-blueprint "SOLAR_DEPLOYMENT" u20 u3))
)