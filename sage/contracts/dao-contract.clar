;; AI-Driven DAO Co-Pilot Smart Contract
;; Designed for intelligent governance analysis and treasury management

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-member (err u101))
(define-constant err-proposal-not-found (err u102))
(define-constant err-voting-closed (err u103))
(define-constant err-already-voted (err u104))
(define-constant err-insufficient-balance (err u105))
(define-constant err-transfer-failed (err u106))
(define-constant err-invalid-proposal (err u107))
(define-constant err-quorum-not-met (err u108))

;; Data Variables
(define-data-var proposal-counter uint u0)
(define-data-var member-counter uint u0)
(define-data-var min-proposal-deposit uint u1000000) ;; 1 STX in micro-STX
(define-data-var voting-period uint u1008) ;; ~7 days in blocks
(define-data-var quorum-threshold uint u51) ;; 51% quorum required

;; Member Management (for AI reputation tracking)
(define-map members
  principal
  {
    joined-at: uint,
    voting-power: uint,
    proposals-created: uint,
    votes-cast: uint,
    reputation-score: uint,
    is-active: bool
  }
)

;; Proposal Structure (AI-friendly with rich metadata)
(define-map proposals
  uint
  {
    title: (string-ascii 100),
    description: (string-utf8 2000),
    category: (string-ascii 30), ;; treasury, governance, technical, etc.
    proposer: principal,
    deposit-amount: uint,
    created-at: uint,
    vote-start: uint,
    vote-end: uint,
    yes-votes: uint,
    no-votes: uint,
    abstain-votes: uint,
    total-voters: uint,
    status: (string-ascii 20), ;; pending, active, passed, failed, executed
    execution-data: (optional (string-utf8 500)), ;; structured data for execution
    ai-analysis-requested: bool,
    risk-level: (optional (string-ascii 10)) ;; low, medium, high (set by AI)
  }
)

;; Individual Vote Records (for AI pattern analysis)
(define-map votes
  {proposal-id: uint, voter: principal}
  {
    vote: (string-ascii 10), ;; yes, no, abstain
    voting-power: uint,
    timestamp: uint,
    rationale: (optional (string-utf8 500)), ;; optional reasoning
    changed-vote: bool ;; track if vote was changed
  }
)

;; Treasury Management
(define-map treasury-proposals
  uint
  {
    recipient: principal,
    amount: uint,
    purpose: (string-utf8 100),
    multi-sig-required: bool,
    approvals: uint,
    executed: bool
  }
)

;; Events for AI monitoring
(define-data-var last-event-id uint u0)

;; Member Functions
(define-public (join-dao)
  (let ((member-id (+ (var-get member-counter) u1)))
    (asserts! (is-none (map-get? members tx-sender)) err-not-member)
    (map-set members tx-sender {
      joined-at: block-height,
      voting-power: u1,
      proposals-created: u0,
      votes-cast: u0,
      reputation-score: u100, ;; starting reputation
      is-active: true
    })
    (var-set member-counter member-id)
    (print {event: "member-joined", member: tx-sender, block: block-height})
    (ok member-id)
  )
)

;; Create Proposal (with AI analysis triggers)
(define-public (create-proposal 
  (title (string-ascii 100))
  (description (string-utf8 2000))
  (category (string-ascii 30))
  (execution-data (optional (string-utf8 500)))
  (request-ai-analysis bool))
  
  (let ((proposal-id (+ (var-get proposal-counter) u1))
        (member-data (unwrap! (map-get? members tx-sender) err-not-member))
        (deposit (var-get min-proposal-deposit)))
    
    ;; Check member status and deposit
    (asserts! (get is-active member-data) err-not-member)
    (asserts! (>= (stx-get-balance tx-sender) deposit) err-insufficient-balance)
    
    ;; Transfer deposit to contract
    (unwrap! (stx-transfer? deposit tx-sender (as-contract tx-sender)) err-transfer-failed)
    
    ;; Create proposal
    (map-set proposals proposal-id {
      title: title,
      description: description,
      category: category,
      proposer: tx-sender,
      deposit-amount: deposit,
      created-at: block-height,
      vote-start: (+ block-height u144), ;; ~24 hours delay
      vote-end: (+ block-height (+ u144 (var-get voting-period))),
      yes-votes: u0,
      no-votes: u0,
      abstain-votes: u0,
      total-voters: u0,
      status: "pending",
      execution-data: execution-data,
      ai-analysis-requested: request-ai-analysis,
      risk-level: none
    })
    
    ;; Update member stats
    (map-set members tx-sender 
      (merge member-data {proposals-created: (+ (get proposals-created member-data) u1)}))
    
    (var-set proposal-counter proposal-id)
    
    ;; Emit event for AI monitoring
    (print {
      event: "proposal-created",
      proposal-id: proposal-id,
      proposer: tx-sender,
      category: category,
      ai-analysis-requested: request-ai-analysis,
      block: block-height
    })
    
    (ok proposal-id)
  )
)

;; Cast Vote (with rationale for AI analysis)
(define-public (cast-vote 
  (proposal-id uint)
  (vote (string-ascii 10))
  (rationale (optional (string-utf8 500))))
  
  (let ((proposal (unwrap! (map-get? proposals proposal-id) err-proposal-not-found))
        (member-data (unwrap! (map-get? members tx-sender) err-not-member))
        (voting-power (get voting-power member-data))
        (existing-vote (map-get? votes {proposal-id: proposal-id, voter: tx-sender})))
    
    ;; Validate voting conditions
    (asserts! (get is-active member-data) err-not-member)
    (asserts! (>= block-height (get vote-start proposal)) err-voting-closed)
    (asserts! (< block-height (get vote-end proposal)) err-voting-closed)
    (asserts! (or (is-eq vote "yes") (is-eq vote "no") (is-eq vote "abstain")) err-invalid-proposal)
    
    ;; Handle vote change if exists
    (match existing-vote
      prev-vote (update-vote-totals proposal-id proposal (get vote prev-vote) vote voting-power true)
      (update-vote-totals proposal-id proposal "" vote voting-power false)
    )
    
    ;; Record vote
    (map-set votes {proposal-id: proposal-id, voter: tx-sender} {
      vote: vote,
      voting-power: voting-power,
      timestamp: block-height,
      rationale: rationale,
      changed-vote: (is-some existing-vote)
    })
    
    ;; Update member stats
    (map-set members tx-sender 
      (merge member-data {
        votes-cast: (+ (get votes-cast member-data) u1),
        reputation-score: (+ (get reputation-score member-data) u1)
      }))
    
    ;; Emit event for AI analysis
    (print {
      event: "vote-cast",
      proposal-id: proposal-id,
      voter: tx-sender,
      vote: vote,
      voting-power: voting-power,
      has-rationale: (is-some rationale),
      block: block-height
    })
    
    (ok true)
  )
)

;; Helper function to update vote totals
(define-private (update-vote-totals 
  (proposal-id uint) 
  (proposal {title: (string-ascii 100), description: (string-utf8 2000), category: (string-ascii 30), proposer: principal, deposit-amount: uint, created-at: uint, vote-start: uint, vote-end: uint, yes-votes: uint, no-votes: uint, abstain-votes: uint, total-voters: uint, status: (string-ascii 20), execution-data: (optional (string-utf8 500)), ai-analysis-requested: bool, risk-level: (optional (string-ascii 10))})
  (old-vote (string-ascii 10))
  (new-vote (string-ascii 10))
  (voting-power uint)
  (is-change bool))
  
  (let ((yes-votes (get yes-votes proposal))
        (no-votes (get no-votes proposal))
        (abstain-votes (get abstain-votes proposal))
        (total-voters (get total-voters proposal)))
    
    ;; Remove old vote if changing
    (let ((updated-yes (if (and is-change (is-eq old-vote "yes")) 
                          (- yes-votes voting-power) yes-votes))
          (updated-no (if (and is-change (is-eq old-vote "no")) 
                         (- no-votes voting-power) no-votes))
          (updated-abstain (if (and is-change (is-eq old-vote "abstain")) 
                              (- abstain-votes voting-power) abstain-votes)))
      
      ;; Add new vote
      (let ((final-yes (if (is-eq new-vote "yes") 
                          (+ updated-yes voting-power) updated-yes))
            (final-no (if (is-eq new-vote "no") 
                         (+ updated-no voting-power) updated-no))
            (final-abstain (if (is-eq new-vote "abstain") 
                              (+ updated-abstain voting-power) updated-abstain))
            (final-voters (if is-change total-voters (+ total-voters u1))))
        
        ;; Update proposal
        (map-set proposals proposal-id 
          (merge proposal {
            yes-votes: final-yes,
            no-votes: final-no,
            abstain-votes: final-abstain,
            total-voters: final-voters
          }))
      )
    )
  )
)

;; Finalize Proposal (check quorum and results)
(define-public (finalize-proposal (proposal-id uint))
  (let ((proposal (unwrap! (map-get? proposals proposal-id) err-proposal-not-found)))
    (asserts! (>= block-height (get vote-end proposal)) err-voting-closed)
    (asserts! (is-eq (get status proposal) "pending") err-invalid-proposal)
    
    (let ((total-votes (+ (+ (get yes-votes proposal) (get no-votes proposal)) (get abstain-votes proposal)))
          (member-count (var-get member-counter))
          (quorum-met (>= (* total-votes u100) (* member-count (var-get quorum-threshold))))
          (proposal-passed (and quorum-met (> (get yes-votes proposal) (get no-votes proposal)))))
      
      (let ((new-status (if quorum-met 
                           (if proposal-passed "passed" "failed")
                           "failed")))
        
        ;; Update proposal status
        (map-set proposals proposal-id (merge proposal {status: new-status}))
        
        ;; Return deposit - check the result properly
        (unwrap! (as-contract (stx-transfer? (get deposit-amount proposal) 
                                          tx-sender (get proposer proposal))) err-transfer-failed)
        
        ;; Emit finalization event
        (print {
          event: "proposal-finalized",
          proposal-id: proposal-id,
          status: new-status,
          yes-votes: (get yes-votes proposal),
          no-votes: (get no-votes proposal),
          abstain-votes: (get abstain-votes proposal),
          quorum-met: quorum-met,
          block: block-height
        })
        
        (ok new-status)
      )
    )
  )
)

;; Read-only functions for data consumption
(define-read-only (get-proposal (proposal-id uint))
  (map-get? proposals proposal-id)
)

(define-read-only (get-vote (proposal-id uint) (voter principal))
  (map-get? votes {proposal-id: proposal-id, voter: voter})
)

(define-read-only (get-member (member principal))
  (map-get? members member)
)

;; Get voting patterns for AI analysis
(define-read-only (get-proposal-stats (proposal-id uint))
  (match (map-get? proposals proposal-id)
    proposal (some {
      total-votes: (+ (+ (get yes-votes proposal) (get no-votes proposal)) (get abstain-votes proposal)),
      yes-percentage: (if (> (+ (+ (get yes-votes proposal) (get no-votes proposal)) (get abstain-votes proposal)) u0)
                         (/ (* (get yes-votes proposal) u100) 
                            (+ (+ (get yes-votes proposal) (get no-votes proposal)) (get abstain-votes proposal)))
                         u0),
      participation-rate: (/ (* (get total-voters proposal) u100) (var-get member-counter)),
      time-remaining: (if (> (get vote-end proposal) block-height) 
                         (- (get vote-end proposal) block-height) u0)
    })
    none
  )
)

;; Treasury functions
(define-public (create-treasury-proposal (recipient principal) (amount uint))
  (let ((proposal-id (+ (var-get proposal-counter) u1)))
    (map-set treasury-proposals proposal-id {
      recipient: recipient,
      amount: amount,
      purpose: u"Treasury transfer",
      multi-sig-required: (> amount u10000000),
      approvals: u0,
      executed: false
    })
    (print {event: "treasury-proposal-created", proposal-id: proposal-id, amount: amount})
    (ok proposal-id)
  )
)

;; Initialize contract
(define-public (initialize)
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (unwrap! (join-dao) err-not-member) ;; Owner joins as first member
    (ok true)
  )
)