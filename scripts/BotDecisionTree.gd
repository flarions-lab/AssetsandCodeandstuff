extends Node
## BotDecisionTree.gd
## Round 8 — Material + Move-Chain rewrite. Scraps every heuristic from rounds
## 1-7 (danger zones, isolation, multi-angle envelopes, advance/offense pulls,
## chain-threat envelopes, beam search...) in favor of one idea: exhaustively
## search single-piece "move chains" — sequences of up to N chain-links, where
## each link is either ONE hex hop (a move-pattern application, possibly a
## capture) or an up-to-300-degree rotation (1-5 rotation steps, only legal on
## edge tiles) — and score each chain purely by the total MATERIAL VALUE of
## enemy pieces captured along the way (see TILE_POSITION_VALUE /
## _get_piece_value). Each rolled movement point = exactly one chain-link,
## matching how GameManager._bot_act spends points per evaluate_position() call.
##
## Each turn (_plan_turn):
##  1. Predict the HUMAN's best move-chain assuming they roll
##     ASSUMED_ROLL_BY_DIFFICULTY[bot_difficulty], to find which of our pieces
##     is most threatened next turn (_search_all_chains over the enemy's
##     pieces, targeting ours).
##  2. Search OUR best move-chain at the ACTUAL rolled movement_points
##     (_search_all_chains over our pieces, targeting theirs).
##  3. Per the standing rule "assume the bot's capturing piece will be lost —
##     act on it only if the capture is net positive or equal; if not, move
##     the threatened piece instead": if our chain's captured value >= the
##     value of the piece that executes it, commit to that chain. Otherwise
##     run the threatened piece away from the human's predicted attacker
##     (_search_escape_chain) — still picking up anything free along the way,
##     still scored by the same chain-link unit of distance.
##
## Cached as _turn_plan and consumed one chain-link per evaluate_position()
## call, exactly like the previous Plan-Then-Execute design.
##
## Round 9 additions (still material + chains only, no new scoring systems):
##  - BOARD CONTROL: _search_all_chains now breaks ties in captured "value"
##    (most commonly the all-zero "nothing capturable" case) by which
##    candidate piece's chain ends in a position that projects into (can reach
##    within BOARD_CONTROL_DEPTH chain-links) the most board squares — see
##    _reachable_squares/_control_score_for_candidate. This is "having more of
##    the board covered in movement chains than the opponent": when material
##    is tied, prefer the move that restricts the opponent's options most.
##    _board_control also prints a simple ours-vs-enemy coverage gauge each
##    turn.
##  - TRADE WHEN AHEAD: the attack/defend choice in _plan_turn now also
##    accepts a net-negative trade if our overall material lead can absorb the
##    loss without putting us at a deficit (material_balance + net >= 0).
##    Mirrors the standard "simplify toward a won endgame when ahead" idea
##    using only the material totals already being tracked.
##
## Round 10 — difficulty modulation:
##  - HUMAN_ASSUMED_ROLL is now ASSUMED_ROLL_BY_DIFFICULTY, keyed by
##    GameManager._current_bot_difficulty(): Easy=3, Medium=4, Hard=5 (the round 8/9
##    value), Extra Hard=5. Lower assumed rolls make the bot predict a
##    shorter/weaker human chain, so it under-rates threats (less likely to
##    trigger "Move Threatened Pieces").
##  - _search_all_chains's target list is now a {pos: sid} map instead of a
##    position Array, and target values come from _piece_value_for_sid(sid)
##    (board-independent) rather than _get_piece_value(pos, board)
##    (board.get_piece_at-dependent) — required for round 11's hypothetical
##    position maps below, which don't (yet) have pieces on the real board.
##
## Round 11 — Extra Hard "every movement possibility" minimax
## (_search_extra_hard), as an ENHANCEMENT layered on top of the proven
## best-chain logic below, not a replacement for it.
##
## _search_extra_hard considers EVERY one of our pieces that has an ACTUAL
## CAPTURE available this turn (_search_chain_for_piece value > 0) — not just
## the single overall-best one — and for each such "attacker" plays out:
## that piece's capture chain -> the human's best reply against the result
## (_apply_chain_move / _apply_chain_captures simulate both) -> our best
## follow-up against THAT. Each candidate is scored
##   candidate.value - human_reply.value + our_followup.value
## and _plan_turn commits to the highest-scoring candidate (subject to the
## same material-balance "trade when ahead" check as Easy/Medium/Hard).
##
## If NO piece can capture anything this turn (the common case), or the best
## attacker's net 2-ply score isn't worth it, _plan_turn falls straight
## through into the SAME best-chain/net/_defend_or_fallback logic Hard uses —
## so Extra Hard never plays worse than Hard, only potentially better when a
## genuinely good capture-then-trade sequence exists. (An earlier version of
## this round let _search_extra_hard also pick among each piece's "nothing to
## capture" filler chain — which _search_chain_for_piece returns with no
## regard for walking that piece into danger — using only the noisy 2-ply
## score; that caused the bot to wander pieces in front of the opponent. This
## revision restricts _search_extra_hard's candidates to actual captures so
## that case can't arise from this code path.)
##
## This runs up to N searches-of-searches (N = our piece count with a capture
## available, usually 0-2), so it's noticeably slower than Hard whenever it has
## something to evaluate — see GameManager/UIManager for the "bot is thinking"
## indicator shown while this runs. Easy/Medium/Hard are unchanged (still
## single best chain + net, see _plan_turn).
##
## Round 12 — "undefended target" bonus (_build_target_values/_is_undefended).
## Whenever the bot evaluates which HUMAN piece to capture (b_result,
## b_result2, and _search_extra_hard's own targets — i.e. every target map
## built FOR the bot, never the ones predicting the human's reply), an enemy
## piece that no OTHER enemy piece could recapture afterward gets +2.0
## (UNDEFENDED_BONUS) added to its normal piece value. "Could recapture" is
## checked with a FIXED assumed roll of 4 chain-links (UNDEFENDED_ASSUMED_ROLL)
## regardless of difficulty. This nudges the bot toward captures that stick —
## taking an undefended piece is now slightly preferred over an equal- or
## near-equal-value piece that the human could immediately take back, and can
## also tip a previously-too-risky trade into "worth it" when the resulting
## capture leaves the bot's piece somewhere the human can't punish.
##
## Round 13 — three additions, all layered on top of the Round 8-12 machinery
## without changing how captures themselves are valued:
##
##  1. GRADUATED defended-target bonus (_count_attackers/_build_target_values,
##     DEFENSE_BONUS_MAX): Round 12's flat +2/binary "undefended" bonus is now
##     a 0/1/2/3+ defenders -> +3/+2/+1/+0 scale (still the bot's own targets
##     only, still a fixed assumed roll of 4).
##
##  2. "Prefer the cheaper piece" tiebreak (item 4): in _search_all_chains, a
##     tie on captured "value" is now broken FIRST by which candidate's own
##     piece (_piece_value_for_sid) is worth less — BEFORE the "control"
##     tiebreak. Same idea in _search_extra_hard: a tie on "score" (with
##     captured "value" not decreasing) prefers the cheaper executing piece.
##     Send the disposable piece to do an equally-good job.
##
##  3. Positional tiebreak (_position_score_for_candidate, item 1) — a NEW 4th
##     tier in _search_all_chains, after "value", the cheaper-piece tiebreak,
##     AND "control" are all tied (i.e. truly "scoring is not an option and
##     repositioning has little value"):
##       - RISK/REWARD: a candidate landing on a square 2+ enemy pieces could
##         reach within a 5-link chain next turn ("from the enemy's
##         perspective") is penalized — addresses the bot struggling to claw
##         back from material loss by walking pieces into multi-attacker
##         squares.
##       - FORWARD/BACK: a piece's mobility (reachable squares within
##         BOARD_CONTROL_DEPTH — "the number of friendly move chains on one
##         piece") and whether its chain moves it closer to or farther from
##         the nearest enemy. Low-mobility pieces are nudged FORWARD
##         (advancing a piece that has nothing better to do); high-mobility
##         pieces are penalized for retreating FARTHER from the front line —
##         addresses the "good early/endgame, aimless midgame" pattern where
##         _control alone doesn't push pieces toward useful squares.
##       - DEFENDED LANDING: bonus per OTHER friendly piece that could reach
##         the candidate's end square within the same fixed roll of 4 — "into
##         a more defended spot".
##     See RISK_CONVERGENCE_*/POSITION_*/DEFENDED_LANDING_WEIGHT below for the
##     exact weights; all three are pure tiebreakers and can never override an
##     actual material difference.
##
## Round 14 — regression fix + multi-piece capture setup, in response to
## "it plays much worse now [after Round 13] but the mid game positioning is
## better [Round 13 item 1 — keep] ... still lacks the desired ability to
## execute capturing with multiple pieces":
##
##  1. REGRESSION FIX — "ranking value" vs. "net value". Round 13's graduated
##     defended-target bonus (DEFENSE_BONUS_MAX, up to +3.0) was being added
##     directly into the SAME "value" that _plan_turn's `net` and
##     _search_extra_hard's `score` use for "is this whole move/sequence
##     materially worth it". Because that bonus is now non-zero for targets
##     with 1 or 2 defenders too (not just 0, as in Round 12's flat
##     UNDEFENDED_BONUS), it could turn a genuinely net-negative trade (the
##     bot loses a pricier piece to capture a cheaper, still-defended one that
##     immediately gets recaptured) into a fake `net >= 0` / `score >= 0`, and
##     the bot would commit to it. This is almost certainly the "plays much
##     worse now".
##
##     Fix: _search_all_chains now ALSO returns "net_value"
##     (_net_captured_value) — pure _piece_value_for_sid for each captured
##     square, plus Round 12's ORIGINAL flat +UNDEFENDED_BONUS_FOR_NET (2.0)
##     per captured square that has ZERO defenders, restored exactly (see
##     UNDEFENDED_BONUS_FOR_NET). _plan_turn's `net` and _search_extra_hard's
##     `score` now use "net_value" instead of "value". The graduated
##     DEFENSE_BONUS_MAX bonus still does its Round 13 job — still baked into
##     "value", which still drives _search_chain_for_piece's choice of WHICH
##     square(s) to capture and _search_all_chains's tier-1 ranking ("prefer
##     the less-defended target when there's a choice") — it just can no
##     longer manufacture a fake "good trade" out of a real one.
##
##  2. OFFENSIVE CONVERGENCE — a new term in _position_score_for_candidate, at
##     the same 4th tier as Round 13's positional tiebreakers (which the user
##     confirmed are working — "mid game positioning is better"):
##     +OFFENSIVE_CONVERGENCE_BONUS if, after this move, 2+ of our pieces
##     could reach some SINGLE enemy piece within UNDEFENDED_ASSUMED_ROLL
##     chain-links — the offensive mirror of the existing risk/reward
##     convergence penalty. Directly targets "execute capturing with multiple
##     pieces": among otherwise-equal repositioning moves, steers pieces
##     toward squares that gang up on the same enemy piece for a future turn.
##
## Round 15 — "dive vs. safe capture", in response to: the user set up two
## equal-value enemy pieces, each a clean SAFE single capture for a different
## one of our pieces ("taking both with the matching pieces should have been
## priority given threat level") — but the bot instead "dove" with ONE piece
## through BOTH enemy pieces in a single 2-link chain. That dove for 1 more
## raw material than either safe single capture ("so it looks better") but
## ended the chain on a DEFENDED square, where the diving piece — the more
## valuable of the two — gets recaptured next turn for what the user correctly
## called "a large net loss":
##
##  1. _net_captured_value (Round 14) double-counted UNDEFENDED_BONUS_FOR_NET
##     on multi-capture chains: it added +UNDEFENDED_BONUS_FOR_NET for EVERY
##     captured square that was (pre-move) undefended — up to +2.0 PER
##     capture, so +4.0 for a 2-capture dive. But the capturing piece only
##     ends the turn on ONE square (the end of the chain); an EARLIER
##     captured square's defenders say nothing about whether the piece
##     executing the chain survives. The spurious +4.0 was easily enough to
##     push `net`/`score` to >= 0 even when the chain's actual END square was
##     heavily defended.
##
##     Fix: the bonus is now checked ONCE, against the chain's FINAL landing
##     square only — squares captured earlier in the SAME chain are removed
##     from the defender count first (_apply_chain_captures), so a piece the
##     bot just captured isn't counted as still "defending" the end square.
##
##  2. NEW _search_safe_chain + _plan_turn fallback. Even with (1) correctly
##     making the dive's `net`/`score` negative, _plan_turn's only recourse
##     when its single best-"value" chain (b_result) isn't net-positive was
##     _defend_or_fallback — which, if h0_result finds no CURRENTLY-threatened
##     piece (the danger here only exists AFTER diving), just executes
##     b_result's chain anyway ("attacking anyway") — the same bad dive.
##     _search_safe_chain searches every piece for the best chain whose OWN
##     net_value - mover_value >= 0: a capture that's worth it even assuming
##     the capturing piece is then lost. When b_result isn't net-positive and
##     the material lead can't absorb it either, _search_safe_chain's result
##     (if any) becomes what "attacking anyway" attacks with instead — take
##     the safe single capture rather than repeat the bad dive. "Move the
##     currently-threatened piece away" (when h0_result finds one) still
##     takes priority, unchanged.
##
## Round 16 — "immediate capture priority", in response to: "still not taking
## pieces with lower value pieces instead still relying on expensive pieces and
## is still not capturing with multiple pieces". Root cause: _search_all_chains
## (b_result) ranks candidates by TOTAL captured value across a piece's WHOLE
## move-chain (up to movement_points links). An expensive piece that can DIVE
## for two captures (total value 20) beats a cheap piece sitting RIGHT NEXT TO
## a free capture (value 8) at tier 1, even though sending the cheap piece and
## keeping the expensive one safe is strictly better — and because _plan_turn
## commits the ENTIRE movement budget to that ONE winning chain, the cheap
## piece's free capture never gets a turn this round either.
##
## _search_immediate_captures runs BEFORE any dive/minimax planning: it checks
## EVERY one of our pieces for a capture reachable with its VERY NEXT (1st)
## movement point at its CURRENT rotation (a one-link hop landing on an
## enemy-occupied square). Candidates are filtered to net-positive (or
## material-lead-absorbable, same "trade when ahead" rule as elsewhere), then
## ranked by captured "value" (tier 1, same graduated defended-target bonus as
## _search_all_chains) and — on a tie — the CHEAPER capturing piece (tier 2,
## same as _search_all_chains). If one qualifies, _plan_turn returns JUST THAT
## ONE LINK as the whole plan.
##
## Returning only one link is the key: evaluate_position re-plans from the
## (now-updated) board every time _turn_plan empties — which, for a 1-link
## plan, is immediately. So on the VERY NEXT call, if a SECOND piece now also
## has its own qualifying immediate capture (it didn't need the first capture
## to happen — it was independently available all along, just previously
## crowded out by the first piece's higher-"value" dive), it gets taken too.
## Multiple different pieces each capturing in the same turn falls out of this
## for free, with no new "multi-piece" search of its own, WHEN each piece's
## capture is independently a 1-link hop. Dives/minimax (_search_extra_hard,
## b_result, _defend_or_fallback, _search_safe_chain) are UNCHANGED and still
## run exactly as before whenever NO immediate capture qualifies — e.g. every
## capture this turn requires 2+ links to set up, or the only immediate
## captures are net-negative trades we're not ahead enough to absorb.
##
## Round 17 — "multi-piece combo", in response to: a test position where two
## different pieces could EACH reach a capture in 2 links (Reposition then
## Capture — NOT a 1-link immediate capture, so _search_immediate_captures
## above found nothing), and at non-Extra-Hard difficulties nothing else
## looked for this either: _search_extra_hard (and the multi-piece combo logic
## that, before this round, lived ONLY inside it) only runs when
## bot_difficulty == 3, so Easy/Medium/Hard never got multi-piece captures
## beyond the 1-link case above.
##
## _search_multi_piece_combo is the promoted, standalone version of that
## combo logic: for every piece with an actual capture available
## (_search_chain_for_piece's "value" > 0), truncate its chain to just its
## FIRST capture (a "leg"). Any pair of DIFFERENT pieces' legs that together
## fit movement_points, hit different squares, and are EACH individually
## net-positive on their own (same "worth it by itself" bar
## _search_safe_chain/_search_immediate_captures use) forms a valid combo:
## piece i captures, then piece j captures, same turn. _plan_turn checks this
## right after _search_immediate_captures, on EVERY difficulty, and takes the
## combo if its combined "value" is >= the best single immediate capture's
## "value". _search_extra_hard's own copy of this logic was removed as
## redundant (see its doc comment).

## Round 18 — "safe filler move", in response to: "sometimes when it receives
## low movement it throws a piece out as bait but doesn't have anything to
## follow up on it if its taken" — i.e. when NOTHING is capturable by ANY of
## our pieces this turn (b_result["value"] <= 0.0, common with a small
## movement roll), _search_all_chains's chosen piece still has to go
## SOMEWHERE, and _search_chain_for_piece's tie-break for an all-zero-value
## chain is "first hop/rotation _cached_moves_rotated happens to list" — pure
## iteration-order luck, with no concept of safety. That could land the piece
## on a square an enemy can reach next turn with no friendly piece able to
## recapture it: bait with no follow-up, exactly as described.
##
## _search_safe_filler_move (called from _plan_turn right after the
## b_result["path"].is_empty() check, only when b_result["value"] <= 0.0)
## enumerates EVERY one of our pieces' EVERY possible first action this turn
## (a hop to an empty, non-enemy-occupied square, or — on an edge tile — a
## 1-5 step rotation), plays out the rest of the chain value-neutrally, and
## scores the landing square as "exposed" (an enemy could reach it within
## UNDEFENDED_ASSUMED_ROLL links) and "defended" (one of OUR OTHER pieces
## could reach it within the same bound, i.e. recapture). "bait" = exposed
## and not defended. It picks a non-bait landing if any piece has one
## (satisfying the user's preferred fix: don't get close to the enemy at all,
## when avoidable), falling back to the least-bad bait option (using
## _position_score_for_candidate as a tiebreak) only if every single
## available action for every piece is bait. _plan_turn substitutes this pick
## for b_result's arbitrary "path"/"start" before the net/material-balance
## checks and _defend_or_fallback run, so "move the currently-threatened piece
## away" (h0_result) still takes priority over this filler move, unchanged.

## Round 19 — "trap capture" detection, in response to: a logged game where
## the bot (Extra Hard) made a 5-link dive that captured a piece for an exact
## "net = 0.0" (capture value == own piece's value, a fair trade in
## isolation) -- but the square it captured INTO had been blocking one of the
## human's own pieces. Capturing it removed that blocker, opening a path that
## let the human's piece chain THROUGH that square (recapturing the bot's
## diving piece) and CONTINUE on to capture a SECOND, completely unrelated
## bot piece in the very same human turn -- a 2-for-1 loss from a move that
## looked perfectly even.
##
## _search_extra_hard's existing 2-ply lookahead (Round 16) had ALREADY
## computed this: for that exact candidate, "immediate_exchange" (what we
## capture now minus the human's best IMMEDIATE reply, i.e. their full
## move-chain value on the post-capture board) was a large negative the
## material lead couldn't absorb, so _search_extra_hard correctly excluded it
## from dive_candidates. But with dive_candidates empty, _search_extra_hard
## returned an empty "path" entirely, and _plan_turn fell through to Hard's
## _search_all_chains-based b_result/"net" logic -- which has NO lookahead at
## all and re-picked the exact same candidate, whose naive "net" (0.0) looked
## fine on its own.
##
## Fix: _search_extra_hard now always returns "candidates" (every piece with
## an actual capture, each with its "immediate_exchange"), regardless of
## whether dive_candidates ended up empty. _plan_turn (when difficulty == 3)
## keeps this list as extra_hard_candidates. After computing b_result, if
## b_result is itself a capture (value > 0) and its "start" matches one of
## extra_hard_candidates with an unaffordable immediate_exchange -- i.e. the
## SAME candidate _search_extra_hard already rejected -- it's a "trap
## capture": b_result["value"]/"net_value" are zeroed and folded into the
## EXACT SAME "nothing safely capturable" branch Round 18 uses, so
## _search_safe_filler_move picks a genuinely safe move instead. At
## difficulty < 3, extra_hard_candidates stays empty and this is a no-op.

## Round 20 — "futile escape" fix, in response to: a logged game (Round 19
## working correctly -- every available capture each turn was a detected TRAP
## and rejected) where the bot still bled from material balance -1 down to
## -31 over many turns, mostly by repeatedly shuffling the SAME piece back and
## forth. Twice in that log, _search_safe_chain found a genuinely net-positive
## capture (net=+1.0, by a DIFFERENT, non-threatened piece) and reported it as
## the fallback ("safer capture from ... available as fallback"), but
## _defend_or_fallback discarded it: it instead ran "Move Threatened Pieces"
## on the piece h0_result said was in danger, and _search_escape_chain --
## which was FORCED to spend every one of its movement points -- could find no
## square farther from danger than the piece's CURRENT square, so it produced
## a multi-link chain that looped right back to the starting square (in one
## case ending with a pointless edge-tile rotation that, per the logged
## material totals, actually COST material). Net effect each of those turns:
## the threatened piece ended up exactly as threatened as before, AND the
## available +1.0 capture was skipped, for literally nothing.
##
## Fix: _search_escape_recursive's search now treats "stop now, use no more
## links" as the baseline at every depth (value = stay_value, the same
## ESCAPE_WEIGHT * hex_distance(pos, danger_pos) metric used for leaves), and
## only takes a hop/rotation if it's STRICTLY better than stopping. A chain
## that can't improve on the piece's current distance from danger (and can't
## capture anything along the way) now returns an EMPTY path instead of a
## forced, value-losing round trip. _defend_or_fallback treats that exactly
## like "no moves at all" and falls through to fallback_path -- e.g. the
## net-positive _search_safe_chain capture computed just before it ran.

## Round 21 — "rotation must not reduce mobility", in response to: a logged
## "Move Threatened Pieces" escape that opened with a 120-degree rotation,
## then immediately re-planned from scratch with a completely different chain
## for the SAME piece -- i.e. the rotation accomplished nothing observable and
## just burned a turn's link. User's rule: a rotation link should only ever be
## chosen if it INCREASES the number of on-board chains available to that
## piece, or at worst leaves it unchanged -- never reduces it.
##
## Fix: new helper _rotation_keeps_or_increases_mobility(pos, sid, rot_offset,
## rot_steps) compares _cached_moves_rotated(pos, sid, rot_offset + rot_steps)
## .size() against the un-rotated count. Every place a chain-link search
## considers a rotation -- _search_chain_for_piece's rotation branch,
## _search_escape_recursive's rotation branch (Round 20's "Move Threatened
## Pieces"), and _search_safe_filler_move's rotation candidates (Round 18) --
## now skips any rot_steps (1-5, i.e. 60-300 degrees) that would shrink this
## piece's immediate move options. This can only narrow what was already being
## searched, so it's a pure restriction, not a new behavior.

## Round 22 — "background" search, in response to: logged _plan_turn calls
## taking 50-62 SECONDS of wall-clock time, severely lagging the whole game
## (the "bot is thinking" spinner, hex glow, camera zoom/rotate/pan all stall
## with it). _search_extra_hard already yielded via
## board.get_tree().process_frame once per candidate piece (Round 11) and once
## more before its 2-ply lookahead (Round 16), but the lookahead itself --
## _search_all_chains, which runs a full _search_chain_for_piece DFS PLUS a
## _reachable_squares board-control flood for EVERY piece on one side -- ran
## with NO yields at all, up to FOUR times per _plan_turn (h0_result, b_result,
## and h_result/b_result2 for each Extra-Hard candidate). On a board with a
## dozen-plus pieces per side, each of those calls alone was almost certainly
## the dominant cost.
##
## Fix: _search_all_chains is now itself a coroutine that yields via
## board.get_tree().process_frame once per piece in its main loop, and all 4
## call sites (_plan_turn's h0_result/b_result, _search_extra_hard's
## h_result/b_result2) now `await` it. This applies on EVERY difficulty (not
## just Extra Hard), since h0_result/b_result run regardless. No search logic
## changed -- this only breaks the same work into per-piece chunks so the rest
## of the engine keeps running between them.

## Round 23 — "doomed piece, take it with you" exception, in response to: a
## logged Extra Hard turn where h0_result predicted the human's next chain
## would capture our piece at (10, 7) for value 9.0, and _search_escape_chain
## confirmed (10, 7) "has no escape that improves its safety" (Round 20) --
## that piece is getting captured next turn NO MATTER WHAT we do this turn.
## That SAME piece's own best chain (value 7.0, immediate_exchange -9.0) was
## flagged a Round 19 TRAP and discarded entirely, and the bot spent its whole
## turn repositioning a different, perfectly safe piece for nothing.
##
## The ledger: if (10, 7) sits still, our material after the human's reply is
## V - h0_result["value"]. If (10, 7) takes its own capture instead, our
## material after the human's (now different) best reply is V + result_net -
## h_result["net_value"], i.e. V + immediate_exchange (immediate_exchange is
## defined as result_net - h_result["net_value"], Round 16). These are the
## same comparison: taking the trade is AT LEAST AS GOOD as sitting still
## exactly when immediate_exchange + h0_result["value"] >= 0 (or, with the
## existing "trade when ahead" absorption, material_balance +
## immediate_exchange + h0_result["value"] >= 0). The loss h0_result already
## predicted is "sunk" either way -- only the INCREMENTAL difference matters.
##
## Fix: in _plan_turn's Round 19 trap check, if b_result's trapped capture is
## made by the SAME piece h0_result's chain would capture first
## (_find_threatened_positions, also shared with _defend_or_fallback) AND
## _search_escape_chain confirms that piece has no improving escape, AND the
## ledger above is >= 0, the TRAP is waived: b_is_trap stays false and
## b_result keeps its original value/path, falling through to the normal net /
## "trade when ahead" checks (which, in the logged case, accepted it: net -2.0
## absorbed by material balance +3, captured the value-7.0 piece instead of a
## pointless reposition). If the ledger is negative -- the trap would cost MORE
## than the already-doomed piece is worth -- the exception doesn't apply and
## Round 19/20's original filler/reposition behavior is unchanged.

## Round 24 — "is the escape actually worth it", in response to: a logged
## Extra Hard turn where h0_result (value 14.0) threatened our MOST valuable
## piece (mover_value 14.0) at (10, 5), _search_safe_chain found a genuinely
## net-positive fallback capture from (10, 3) (net 1.0), and
## _search_escape_chain returned a non-empty 4-link path (10,5)->(9,6)->
## (7,7)->(6,8)->(6,10) with ZERO captures. _defend_or_fallback took that
## escape unconditionally and discarded the net=1.0 fallback entirely --
## spending the ENTIRE turn moving the bot's most valuable piece a few hexes
## while a perfectly good capture sat on the table. Per the user: "this is
## clearly a logic error moving the most valuable piece only 2 spaces out i
## was hoping it would do something else then roll a 5 and take 3 gray
## pieces".
##
## The root cause: Round 20's _search_escape_chain only guarantees a non-empty
## result beats STANDING STILL by its hex_distance(pos, danger_pos)*
## ESCAPE_WEIGHT heuristic. With assumed_roll often 5 (Extra Hard) and this
## board's reach, a 4-link reposition can increase that raw hex distance
## without actually getting the piece outside the human's real chain-reach --
## i.e. h0's NEXT best reply might still capture roughly the same value, just
## via a different path. _defend_or_fallback never checked that; it only
## checked "is escape non-empty", then ran with it over ANY fallback_path.
##
## Fix: when _search_escape_chain returns non-empty AND fallback_path is also
## non-empty (Round 24 has nothing to compare against if fallback_path is
## empty -- escaping is free in that case), play the escape out --
## enemy_after_escape = _apply_chain_captures(enemy_sid_map, escape["path"]),
## mine_after_escape = _apply_chain_move(my_sid_map, threatened_pos,
## escape["path"]) -- and re-run h0_after = _search_all_chains(board,
## enemy_after_escape, mine_after_escape, assumed_roll). The escape's total
## value is escape_value (its own captures, _net_captured_value with the
## undefended bonus) plus threat_reduction (h0_result["value"] -
## h0_after["value"], i.e. how much the human's best reply got WORSE for them
## because we escaped). If escape_value + threat_reduction <= fallback_net,
## the escape didn't earn its keep -- use fallback_path (the (10,3) net=1.0
## capture in the logged case) instead. Otherwise the escape really did
## defuse a threat worth more than the fallback, so take it.
##
## This costs one extra _search_all_chains call, but ONLY when BOTH a
## non-empty escape AND a non-empty fallback exist -- the narrow case Round 20
## couldn't distinguish on its own.

## Round 25 — "defend the dive, or quit it and advance elsewhere". Rounds 19
## and 23 decide WHETHER b_result's best capture is a TRAP (its dive lands
## somewhere the human's best reply recaptures for more than it's worth, and
## we can't afford or absorb that, and it isn't a doomed piece worth taking
## with us). Previously, once b_is_trap was true, _plan_turn went STRAIGHT to
## Round 18's general _search_safe_filler_move -- which searches EVERY piece's
## EVERY first action for "not bait", with no preference for what happens to
## the TRAPPED piece specifically. It might re-offer that same piece's own
## best (still-bait) move, or pick some unrelated piece's shuffle, while the
## trapped piece either dives anyway via an earlier branch or sits exactly
## where the trap left it exposed.
##
## Fix: when b_is_trap, before Round 18 runs, try two options FOR THE TRAPPED
## PIECE specifically:
##   1. _search_defend_piece(board, my_sid_map, enemy_sid_map,
##      b_result["start"], movement_points) -- "defend the piece with movement
##      instead of moving forward [into the dive]". Same per-piece first-action
##      enumeration as _search_safe_filler_move (hop or edge-tile rotation, NOT
##      the dive), but only counts a landing as useful if it's NOT bait (no
##      enemy reaches it, or one of our other pieces could recapture there).
##      Returns {"path": [], "position": -INF} if nothing the piece can do
##      this turn avoids bait.
##   2. _search_safe_filler_move(..., exclude_pos=b_result["start"]) -- the
##      existing Round 18 search, but with the trapped piece excluded, so it
##      can only suggest a DIFFERENT piece's move. This is "quit moving the
##      piece in the doomed position and use your movement elsewhere" --
##      usually an advance that claims board space, since
##      _position_score_for_candidate's forward/back weighting already favors
##      that among non-bait candidates.
##
## _plan_turn picks #1 (defend in place) UNLESS #2 is available AND scores at
## least as well by _position_score_for_candidate -- i.e. "defend the piece,
## or if that's not possible, or a better outcome [advancing a different
## piece] is possible, leave the trapped piece alone and advance elsewhere
## instead." Either way b_is_trap is cleared and b_result["value"]/
## ["net_value"] are zeroed, same as Round 18's filler. If NEITHER option finds
## a non-bait move, b_is_trap stays true and Round 18's original general
## filler search runs unchanged.

## Round 26 — "what to do with movement left over after a dive's last
## capture", per the user's logic tree:
##   if piece is diving and captures piece(s) with movement remaining ->
##     is the piece safe afterward?
##       yes -> stay, move a different piece with the remaining moves
##       no  -> can I defend this piece with the remaining rolled moves?
##         no  -> piece is doomed, move a different piece with remaining moves
##         yes -> would defending give the opponent a higher assumed score
##                than leaving it doomed and moving elsewhere instead?
##                  yes -> piece is doomed, move a different piece instead
##                  no  -> defend the piece
##
## Why this is needed: _search_chain_for_piece's DFS (Round 8) always returns
## a path of EXACTLY movement_points links -- the _turn_plan invariant
## (evaluate_position requires _turn_plan.size() == movement_points). Once a
## dive has captured everything it's going to, the DFS still has to fill the
## REMAINING links with SOMETHING: any continuation with total >= 0 beats the
## initial -1.0 floor, so it picks whichever hop/rotation it explored first --
## with zero regard for whether THAT leaves the diving piece sitting somewhere
## exposed, or wanders it away from useful board space, while a perfectly good
## "move a different piece" use of those same links goes untaken.
##
## _allocate_post_dive_movement (called from _plan_turn's two "commit to
## b_result's dive" returns -- net >= 0, and "trade when ahead") finds the
## LAST capture link in the about-to-be-committed path and splits it into
## capture_path (through that link) and tail_path (everything after). If
## tail_path is empty, nothing to do. Otherwise:
##   - landing_pos = where capture_path ends, board state AFTER its captures.
##   - "is the piece safe afterward?" = NOT (exposed via _count_attackers
##     against the enemy AND undefended via _count_attackers against our other
##     pieces) -- the same bait test _search_safe_filler_move /
##     _search_defend_piece use.
##   - "stay and move a different piece" / "piece is doomed, move a different
##     piece" both mean the same replacement: tail_path becomes
##     _search_safe_filler_move's best non-bait pick for a DIFFERENT piece
##     (exclude_pos=landing_pos), using tail_path.size() links --
##     _position_score_for_candidate's forward-weighting naturally favors an
##     advance/board-space move here.
##   - "can I defend this piece with the remaining rolled moves" =
##     _search_safe_continuation (the same Round 25 helper
##     _search_defend_piece uses, generalized to start from landing_pos at its
##     accumulated rotation with tail_path.size() links) finds a non-bait
##     landing for THIS piece.
##   - "would defending give the opponent a higher assumed score" — when BOTH
##     a defend continuation AND a different-piece advance exist, play each
##     out (_apply_chain_move/_apply_chain_captures) and compare
##     _predict_human_reply(board, enemy_after_X, mine_after_X,
##     assumed_roll)["value"] for the human's best reply in each resulting
##     position. Defending wins only if it leaves the human's best reply NO
##     BETTER for them than leaving this piece doomed and advancing elsewhere
##     would.
##
## Always returns a path of the same length as its input -- if the chosen
## replacement for tail_path doesn't come out to exactly tail_path.size()
## links (e.g. every other piece is a genuine dead end), the original path is
## returned unchanged rather than risk breaking the _turn_plan invariant. The
## extra _search_all_chains calls (up to two) only run in the narrowest case:
## landing_pos is bait, AND a same-piece defend exists, AND a different-piece
## advance also exists to compare it against.

## Round 27 — finer-grained yielding inside _search_all_chains, in response
## to: Round 22 stopped the multi-second total freezes by yielding once per
## PIECE, but each piece's own chunk (a full _search_chain_for_piece DFS to
## depth `max_links`, branching up to ~11 ways per level: 6 hex hops + up to 5
## edge-tile rotations) can ITSELF take several-to-tens of milliseconds on a
## crowded board -- enough to spike a single frame and make the "bot is
## thinking" spinner, the animated backgrounds (Hex Drones > Backgrounds), and
## piece-movement tweens all stutter on that frame, even though the game never
## fully locks up.
##
## Fix: _search_chain_for_piece itself is UNCHANGED (so its result for any
## given (pos, sid, own_blocked, targets, links_left, rot_offset) is bit-for-
## bit identical, preserving _search_all_chains's ranking/tie-breaking
## exactly). A new wrapper, _search_chain_yielding, replicates ONLY
## _search_chain_for_piece's TOP-LEVEL loop over this piece's first hop/
## rotation options (the same "better" comparison, same dead-end fallback),
## calling the unchanged _search_chain_for_piece for each branch's
## links_left-1 sub-search. Between top-level branches, it checks a small
## wall-clock budget (CHAIN_YIELD_BUDGET_USEC) and -- only if exceeded --
## awaits board.get_tree().process_frame before continuing. _search_all_chains
## now `await`s this wrapper instead of calling _search_chain_for_piece
## directly.
##
## Net effect: the SAME total computation for the SAME final answer, just cut
## into smaller (roughly /6-to-/11) pieces, so no single frame during bot
## "thinking" does more than ~CHAIN_YIELD_BUDGET_USEC worth of search work no
## matter how deep/expensive an individual piece's chain search gets. The bot
## may take a few more frames overall (imperceptible -- it was already
## spinning for whole seconds), but every frame in between stays smooth.

class_name BotDecisionTree

var game_manager: Node

## Per-evaluation cache for get_valid_move_coords_for_rotated results, keyed by
## "x,y|sid|rot_steps". Purely geometric (board shape + tile rotation only —
## independent of piece occupancy), so it's safe to reuse across the many
## simulated hops within one evaluate_position call. Cleared at the top of
## evaluate_position since rotations can change between bot turns.
var _geo_moves_cache: Dictionary = {}

## board_version (see GameManager._touch_state) the cache was last
## cleared/primed for. evaluate_position only clears _geo_moves_cache when
## this no longer matches the board's current version — i.e. when some move
## or rotation happened since. Lets prewarm_move_cache's work (run during the
## bot's roll-dice delay, before movement_points is even known) survive into
## the evaluate_position call that follows it.
var _geo_cache_version: int = -1

## Cached full-turn plan. Each entry is one chain-link, in one of two shapes:
##   {"type": "move",   "from": Vector2i, "to": Vector2i, "captured": bool}
##   {"type": "rotate", "at": Vector2i, "degrees": float}
## Built once per turn by _plan_turn() and consumed one link per
## evaluate_position() call. Invalidated (and rebuilt) if its size no longer
## matches the remaining movement_points or its next link is no longer legal —
## e.g. because the GameManager's dive-continuation logic executed an extra hop
## out-of-band.
var _turn_plan: Array = []
var _bot_thread_result: Dictionary = {}
## Round 58 — tracks piece positions that were already rotated this turn so
## filler searches don't re-rotate the same piece after a replan (spinning fix).
var _rotated_this_turn: Dictionary = {}

## Ideal chain distance from a bot piece to the nearest enemy when repositioning.
const TARGET_DIST := 3
## BFS depth cap for all distance checks.
const MAX_DIST    := 8
## Assumed movement roll for predicting the human's best capture next turn.
const ASSUMED_HUMAN_ROLL := 5

func _init(gm: Node) -> void:
	game_manager = gm
## ══════════════════════════════════════════════════════════════════════
## MAIN ENTRY POINT
## ══════════════════════════════════════════════════════════════════════

## NOTE: this is a coroutine — _plan_turn yields per-piece inside
## Round 45: evaluate_position is now fully synchronous (all `await` calls
## removed). GameManager calls it via evaluate_position_in_thread on a
## background Thread so the engine main loop stays responsive during the search.
func evaluate_position(board: Node2D, my_pieces: Array, enemy_pieces: Array,
					   _current_player: int, movement_points: int,
					   bot_revenge: Dictionary, recent_squares: Array) -> Dictionary:
	## Enemy source_ids that captured our drones during the human's last turn →
	## worth extra to take back (see REVENGE_VALUE_BONUS, used in _plan_turn).
	_revenge = bot_revenge
	## Round 30 — only clear the geometry cache if the board changed since it
	## was last cleared/primed (see _geo_cache_version / prewarm_move_cache).
	## If GameManager prewarmed it during the roll-dice delay and nothing has
	## moved since, reuse that work instead of throwing it away.
	if _geo_cache_version != game_manager.get_board_version():
		_geo_moves_cache.clear()
		_geo_cache_version = game_manager.get_board_version()

	## A new turn always starts with an empty recent_squares (cleared in
	## roll_dice_bot). Drop any leftover plan from a previous turn.
	if recent_squares.is_empty():
		_turn_plan.clear()
		_rotated_this_turn.clear()

	var my_sid_map: Dictionary = {}
	for p in my_pieces:
		my_sid_map[p] = int(board.get_piece_at(p).get("source_id", -1))

	## — Continue the cached plan if it still matches reality —
	if not _turn_plan.is_empty():
		if _turn_plan.size() == movement_points:
			var step: Dictionary = _turn_plan[0]
			if _plan_step_valid(step, my_sid_map, board):
				_turn_plan.pop_front()
				return _step_to_action(step, board)
		_turn_plan.clear()

	## — Build a fresh full-turn plan —
	var enemy_sid_map: Dictionary = {}
	for p in enemy_pieces:
		enemy_sid_map[p] = int(board.get_piece_at(p).get("source_id", -1))

	_turn_plan = _plan_turn(board, my_sid_map, enemy_sid_map, movement_points)

	if _turn_plan.is_empty():
		return _fallback_any_move(board, my_sid_map)

	var first: Dictionary = _turn_plan.pop_front()
	return _step_to_action(first, board)

## Round 45 — thread entry-point called by GameManager via Thread.start().
## Stores the result in _bot_thread_result so the main thread can read it
## after wait_to_finish(). Void return because Thread.start requires a Callable
## that returns void (or the return value is discarded anyway).
func evaluate_position_in_thread(board: Node2D, my_pieces: Array, enemy_pieces: Array,
								 current_player: int, movement_points: int,
								 bot_revenge: Dictionary, recent_squares: Array) -> void:
	_bot_thread_result = evaluate_position(board, my_pieces, enemy_pieces, current_player, movement_points, bot_revenge, recent_squares)

## A cached step is valid if our piece is still where the plan expects.
## - "move" links: target still geometrically reachable in one hop AT THE
##   PIECE'S CURRENT ROTATION (any rotation links earlier in this same plan
##   were already committed to the board, so _cached_moves_rotated(.., 0)
##   already reflects them), not blocked by our own piece, and the board
##   itself agrees the move is legal.
## - "rotate" links: our piece is still on that square and it's still an edge
##   tile (rotation eligibility is a board-tile property and can't change
##   mid-turn, but the piece could have been moved/captured out of band by the
##   dive-continuation logic).
func _plan_step_valid(step: Dictionary, my_sid_map: Dictionary, board: Node2D) -> bool:
	if step["type"] == "rotate":
		var at: Vector2i = step["at"]
		if not my_sid_map.has(at): return false
		return board.is_edge_tile(at)
	var from: Vector2i = step["from"]
	var to: Vector2i = step["to"]
	if not my_sid_map.has(from): return false
	if my_sid_map.has(to): return false
	var sid: int = my_sid_map[from]
	if not _cached_moves_rotated(from, sid, 0).has(to): return false
	return board.is_valid_move(from, to)

## Convert one _turn_plan chain-link into the action dict GameManager._bot_act
## expects. "rotate_only"+"from" matches its "Handle Rotate-only (pure mobility
## rotation)" branch (board.commit_rotate_piece, then spends 1 movement point).
## "Capture"/"Reposition"+"from"/"to" matches its "Handle all capture actions"
## branch (select_piece_bot + move_selected_piece_to, also 1 point). Both
## branches spend exactly 1 movement point per call — exactly 1 chain-link.
func _step_to_action(step: Dictionary, _board: Node2D) -> Dictionary:
	if step["type"] == "rotate":
		_rotated_this_turn[step["at"]] = true
		return {"action": "Rotate", "from": step["at"], "rotate_only": step["degrees"], "score": 0.0}
	var act: String = "Capture" if step["captured"] else "Reposition"
	return {"action": act, "from": step["from"], "to": step["to"], "score": 0.0}

## CRITICAL: evaluate_position must always return a move while any exists.
## Last-resort scan if planning somehow produced nothing.
func _fallback_any_move(board: Node2D, my_sid_map: Dictionary) -> Dictionary:
	for from in my_sid_map.keys():
		var sid: int = my_sid_map[from]
		for to in _cached_moves_rotated(from, sid, 0):
			if my_sid_map.has(to): continue
			if not board.is_valid_move(from, to): continue
			var pt: Dictionary = board.get_piece_at(to)
			var act: String = "Capture" if not pt.is_empty() else "Reposition"
			return {"action": act, "from": from, "to": to, "score": 0.0}
	return {}
## BFS minimum hop count from `start` to any key in `targets`.
## `blocked` = positions treated as walls (other friendly pieces minus start).
## Returns MAX_DIST+1 if unreachable within MAX_DIST hops.
func _bfs_dist(board: Node2D, start: Vector2i, sid: int,
			   blocked: Dictionary, targets: Dictionary) -> int:
	if targets.has(start):
		return 0
	var visited: Dictionary = {start: true}
	var frontier: Array = [start]
	for depth in range(1, MAX_DIST + 1):
		var next: Array = []
		for pos in frontier:
			for to in _cached_moves_rotated(pos, sid, 0):
				if visited.has(to) or blocked.has(to):
					continue
				if targets.has(to):
					return depth
				visited[to] = true
				next.append(to)
		frontier = next
		if frontier.is_empty():
			break
	return MAX_DIST + 1

## BFS path (list of positions after `start`) from `start` to a key in `targets`,
## avoiding `blocked`, within `budget` hops. Returns [] if unreachable.
## Targets are reachable (landing on them is the goal); blocked positions are walls.
## `rot` = rotation offset the drone is moving at (default 0 = current facing).
## A drone that rotated once on its edge tile then moves carries that offset for
## the whole path, so all hops use the same rotated move pattern.
func _bfs_path(_board: Node2D, start: Vector2i, sid: int,
			   blocked: Dictionary, targets: Dictionary, budget: int, rot: int = 0) -> Array:
	var visited: Dictionary = {start: true}
	var frontier: Array = [start]
	var parent: Dictionary = {}
	for _depth in range(budget):
		var next: Array = []
		for pos in frontier:
			for to in _cached_moves_rotated(pos, sid, rot):
				if visited.has(to): continue
				if blocked.has(to): continue
				visited[to] = true
				parent[to] = pos
				if targets.has(to):
					var path: Array = []
					var cur: Vector2i = to
					while cur != start:
						path.push_front(cur)
						cur = parent[cur]
					return path
				next.append(to)
		frontier = next
		if frontier.is_empty():
			break
	return []

## Material value of a piece by source_id (sid).
## Higher value = more important to capture / protect.
func _piece_value(sid: int) -> float:
	match sid:
		6, 16:       return 24.0
		7, 17, 70:   return 14.0
		0, 1, 11, 18: return 6.0
		_:           return 8.0

## Total material value of all drones in a sid_map.
func _total_material(sid_map: Dictionary) -> float:
	var total: float = 0.0
	for p in sid_map:
		total += _piece_value(sid_map[p])
	return total

## All enemies reachable in exactly 1 hop by any bot piece.
## Each enemy position is only claimed once (first piece wins).
func _find_direct_captures(board: Node2D, my_sid_map: Dictionary,
							enemy_sid_map: Dictionary) -> Array:
	var result: Array = []
	var claimed: Dictionary = {}
	for from_pos in my_sid_map:
		var sid: int = my_sid_map[from_pos]
		for to in _cached_moves_rotated(from_pos, sid, 0):
			if claimed.has(to) or not enemy_sid_map.has(to): continue
			if not board.is_valid_move(from_pos, to): continue
			result.append({"from": from_pos, "to": to})
			claimed[to] = true
	return result

## Number of enemy pieces that can reach `pos` within ASSUMED_HUMAN_ROLL hops.
## Each threatening drone reduces the resting-position score by 1 (multiplied first).
func _count_enemy_threats(board: Node2D, pos: Vector2i, enemy_sid_map: Dictionary) -> int:
	var count: int = 0
	var all_enemy: Dictionary = {}
	for p in enemy_sid_map: all_enemy[p] = true
	var target: Dictionary = {pos: true}
	for from_pos in enemy_sid_map:
		var sid: int = enemy_sid_map[from_pos]
		var blocked: Dictionary = all_enemy.duplicate()
		blocked.erase(from_pos)
		if _bfs_dist(board, from_pos, sid, blocked, target) <= ASSUMED_HUMAN_ROLL:
			count += 1
	return count

## Number of friendly pieces in attacker_map that can reach `pos` within `budget` hops.
## Each friendly drone threatening an enemy piece increases that enemy's capture value by 1.
func _count_friendly_threats(board: Node2D, pos: Vector2i,
							   attacker_map: Dictionary, budget: int) -> int:
	var count: int = 0
	var all_att: Dictionary = {}
	for p in attacker_map: all_att[p] = true
	var target: Dictionary = {pos: true}
	for from_pos in attacker_map:
		var sid: int = attacker_map[from_pos]
		var blocked: Dictionary = all_att.duplicate()
		blocked.erase(from_pos)
		if _bfs_dist(board, from_pos, sid, blocked, target) <= budget:
			count += 1
	return count

## Approximate distance to nearest other friendly piece (Chebyshev / grid max).
## Spacing tiebreaker only — does not need to be exact.
func _nearest_friendly_dist(pos: Vector2i, my_set: Dictionary) -> int:
	var best: int = 99
	for p in my_set:
		if p == pos: continue
		var d: int = max(abs(p.x - pos.x), abs(p.y - pos.y))
		if d < best:
			best = d
	return best

## Greedy reposition: each step moves the piece that most improves its distance
## toward `target_dist` from the nearest enemy, with a light bonus for spreading
## away from friendly clusters (friendly spacing used only here).
## target_dist=1 moves aggressively adjacent; TARGET_DIST=3 for resting position.
func _reposition_steps(board: Node2D, my_sid_map: Dictionary,
						enemy_sid_map: Dictionary, budget: int, target_dist: int) -> Array:
	var plan: Array = []
	var cur_my: Dictionary = my_sid_map.duplicate()
	var enemy_set: Dictionary = {}
	for p in enemy_sid_map:
		enemy_set[p] = true

	for _i in range(budget):
		var my_set: Dictionary = {}
		for p in cur_my:
			my_set[p] = true

		var best_from: Vector2i = Vector2i(-1, -1)
		var best_to: Vector2i   = Vector2i(-1, -1)
		var best_score: float   = -1e9

		for from_pos in cur_my:
			var sid: int = cur_my[from_pos]
			var blocked: Dictionary = my_set.duplicate()
			blocked.erase(from_pos)
			var cur_dist: int = _bfs_dist(board, from_pos, sid, blocked, enemy_set)

			for to in _cached_moves_rotated(from_pos, sid, 0):
				if my_set.has(to) or enemy_set.has(to): continue
				if not board.is_valid_move(from_pos, to): continue

				var new_dist: int = _bfs_dist(board, to, sid, blocked, enemy_set)
				var dist_gain: float = float(abs(cur_dist - target_dist) - abs(new_dist - target_dist))
				var spacing_gain: float = float(_nearest_friendly_dist(to, blocked) - _nearest_friendly_dist(from_pos, blocked)) * 0.4
				var threat_penalty: float = float(_count_enemy_threats(board, to, enemy_sid_map)) * 1.0
				var score: float = dist_gain + spacing_gain - threat_penalty

				if score > best_score:
					best_score = score
					best_from  = from_pos
					best_to    = to

		if best_from.x < 0:
			break

		plan.append({"type": "move", "from": best_from, "to": best_to, "captured": false})
		var moved_sid: int = cur_my[best_from]
		cur_my.erase(best_from)
		cur_my[best_to] = moved_sid

	return plan

## Execute as many captures as fit in budget, one per bot piece.
func _plan_multi_capture(captures: Array, movement_points: int) -> Array:
	var plan: Array = []
	var used_from: Dictionary = {}
	for cap in captures:
		if plan.size() >= movement_points: break
		if used_from.has(cap["from"]): continue
		plan.append({"type": "move", "from": cap["from"], "to": cap["to"], "captured": true})
		used_from[cap["from"]] = true
	return plan

## Execute one capture then fill remaining budget with reposition steps.
func _plan_capture_then_reposition(board: Node2D, cap: Dictionary,
									my_sid_map: Dictionary, enemy_sid_map: Dictionary,
									movement_points: int) -> Array:
	var plan: Array = [{"type": "move", "from": cap["from"], "to": cap["to"], "captured": true}]
	var remaining: int = movement_points - 1
	if remaining <= 0:
		return plan
	var new_my: Dictionary = my_sid_map.duplicate()
	new_my.erase(cap["from"])
	new_my[cap["to"]] = my_sid_map[cap["from"]]
	var new_enemy: Dictionary = enemy_sid_map.duplicate()
	new_enemy.erase(cap["to"])
	plan.append_array(_reposition_steps(board, new_my, new_enemy, remaining, TARGET_DIST))
	return plan

## When no enemy is 1-hop adjacent but one is reachable within budget:
## BFS-path the best-value enemy, chain-move all hops in one turn, capture on
## the final hop, then fill remaining budget with reposition steps.
func _plan_advance_and_capture(board: Node2D, my_sid_map: Dictionary,
								enemy_sid_map: Dictionary, movement_points: int) -> Array:
	var all_att: Dictionary = {}
	for p in my_sid_map: all_att[p] = true

	var best_val: float    = -1.0
	var best_from: Vector2i = Vector2i(-1, -1)
	var best_target: Vector2i = Vector2i(-1, -1)
	var best_path: Array   = []

	for target_pos in enemy_sid_map:
		var mat_val: float = _piece_value(enemy_sid_map[target_pos])
		for from_pos in my_sid_map:
			var sid: int = my_sid_map[from_pos]
			var blocked: Dictionary = all_att.duplicate()
			blocked.erase(from_pos)
			for ep in enemy_sid_map:
				if ep != target_pos:
					blocked[ep] = true
			var path: Array = _bfs_path(board, from_pos, sid, blocked, {target_pos: true}, movement_points)
			if path.is_empty():
				continue
			## Material first; path length breaks ties
			if mat_val > best_val or (mat_val == best_val and path.size() < best_path.size()):
				best_val    = mat_val
				best_from   = from_pos
				best_target = target_pos
				best_path   = path

	if best_from.x < 0:
		return []

	var sid: int = my_sid_map[best_from]
	var plan: Array = []
	var cur_pos: Vector2i = best_from
	for i in range(best_path.size()):
		var to: Vector2i = best_path[i]
		var is_capture: bool = (i == best_path.size() - 1)
		plan.append({"type": "move", "from": cur_pos, "to": to, "captured": is_capture})
		cur_pos = to

	var remaining: int = movement_points - best_path.size()
	if remaining > 0:
		var new_my: Dictionary = my_sid_map.duplicate()
		new_my.erase(best_from)
		new_my[best_target] = sid
		var new_enemy: Dictionary = enemy_sid_map.duplicate()
		new_enemy.erase(best_target)
		plan.append_array(_reposition_steps(board, new_my, new_enemy, remaining, TARGET_DIST))

	return plan

## Decision tree:
##
##   my_value    = highest piece value the bot can capture this turn (rolled mp)
##   human_value = highest piece value the human could capture next turn (assumed 5 mp)
##
##   my_value >= human_value  (bot turn value is higher or equal):
##     2+ adjacent enemies  -> multi-capture
##     1 adjacent enemy     -> capture + reposition to TARGET_DIST
##     enemy reachable      -> advance-and-capture this turn (full chain)
##     none reachable       -> advance toward enemy (target_dist=1 to close gap)
##
##   human_value > my_value  (human turn value is higher):
##     capture available    -> take the most threatening enemy, reposition rest
##     enemy reachable      -> advance-and-capture to reduce human's value
##     none available       -> reposition away to TARGET_DIST
## ══════════════════════════════════════════════════════════════════════
## HYBRID SEARCH — evaluation foundation (Round 59)
## ══════════════════════════════════════════════════════════════════════
## Difficulty is a PERCEPTION HORIZON: the max chain-distance at which the bot
## reacts to OTHER drones (friendly or opposing). Easy ignores a drone 4+ chains
## away; Medium reacts within 4; Hard / Extra-Hard within 5. The 3-chain SAFETY
## distance (TARGET_DIST) is constant across difficulties — only perception
## scales. Index = GameManager._current_bot_difficulty() (0..3).
const PERCEPTION_BY_DIFFICULTY := [3, 4, 5, 5]

## Omni Trix (the Genetically Superior) — a tighter perception than Hard (4 chains,
## not 5) but two extra plies of lookahead: it folds the opponent's reply, OUR
## recapture, and the opponent's follow-up into one deep material exchange, so it
## won't fear an exposure it can recapture and it spots multi-turn losing trades.
const OMNI_HORIZON     := 4
const OMNI_EXTRA_PLIES := 2

## Candy Tech (Sugar Princess engineering) — a tight 3-chain horizon but a very
## deep 4 extra plies of exchange lookahead, plus rotation toward the enemy bulk.
const CANDY_HORIZON     := 3
const CANDY_EXTRA_PLIES := 4

## Evaluation weights (tunable; balanced so a single capture rarely justifies
## exposing an equal-value drone, but a multi-capture dive does).
const W_MATERIAL       := 10.0   ## per point of enemy material captured this turn
const W_EXPOSE         := 8.0    ## per point of OUR material the opponent can take next turn
const PENALTY_EXPOSE_2 := 200.0  ## cardinal rule #2 cliff: opponent can capture >1 of our drones
const W_SAFETY         := 4.0    ## per drone, for resting within TARGET_DIST chains of a friendly
const W_CONTROL        := 0.5    ## per reachable square (board control; Extra-Hard only)
const EASY_NOISE       := 30.0   ## ± score jitter on Easy so it makes beatable mistakes
## Per-difficulty caution: how much the opponent-reply (exposure) penalty is
## weighted. Lower = more aggressive (commits to captures even at some risk).
## Easy is intentionally the boldest. Index = difficulty 0..3.
const EXPOSE_CAUTION   := [0.7, 0.6, 1.0, 1.0]
const PATIENCE_PENALTY := 45.0   ## discourage a small defended capture when a bigger multi-cap is brewing (Hard+)

## Double-line drones. They only capture when the trade is favourable: captured
## material must EXCEED the double-line drone's own value, or merely EQUAL it when
## we're already ahead in total material. Cheaper trades are forbidden via
## FORBID_DL_TRADE. Set per the game's piece designations (tile-5/6/7 families).
const DOUBLE_LINE_SIDS := [5, 15, 21, 50, 6, 7, 17, 22, 70]
const FORBID_DL_TRADE  := 100000.0
## +material value added to an enemy drone that captured one of ours during the
## human's most recent turn (revenge target). Set each turn from GameManager.
var _revenge: Dictionary = {}
const REVENGE_VALUE_BONUS := 4.0
## Priority-take: capturing an enemy drone within this many movement chains of one
## of our drones earns PRIORITY_TAKE_BONUS, so the bot clears nearby threats first.
const PRIORITY_TAKE_RANGE := 3
const PRIORITY_TAKE_BONUS := 15.0
## Bey profile: chance per no-capture turn that it rotates a drone toward the enemy
## majority instead of advancing (its "Master of the Rotating Blade" flavour).
const BEY_ROTATE_CHANCE := 0.4
## Endgame defence: the exposure penalty is multiplied by this once few drones
## remain (<= LATE_GAME_PIECES), so the bot guards its pieces much harder when
## every loss is decisive. Tunable — raise for more cautious endgame play.
const ENDGAME_EXPOSE_MULT := 2.0

## Opening rotation — the bot turns its asymmetric P2 drones to a fixed preferred
## orientation on the first turn, then leaves them: tile 13 -> 60 degrees, tile 14
## -> 300 degrees. Held until the late game (see LATE_GAME_PIECES).
const OPENING_ROTATION := { 13: 60.0, 14: 300.0 }
## Once total drones on the board drop to this many or fewer, the fixed opening
## orientation is no longer worth keeping — drones may rotate tactically again to
## reach captures their current facing can't.
const LATE_GAME_PIECES := 6

## Per-instance RNG for Easy-difficulty score noise (thread-safe: only the bot
## thread touches it, one bot turn at a time).
var _rng := RandomNumberGenerator.new()

func _perception_horizon() -> int:
	match game_manager.active_bot_profile_id:
		"omnitrix":  return OMNI_HORIZON
		"candytech": return CANDY_HORIZON
	return PERCEPTION_BY_DIFFICULTY[clampi(game_manager._current_bot_difficulty(), 0, 3)]

## Extra plies of exchange lookahead beyond the base 1-ply opponent reply. Omni Trix
## (2) and Candy Tech (4) look deeper; every other profile stays at the cheaper
## 1-ply model.
func _extra_reply_plies() -> int:
	match game_manager.active_bot_profile_id:
		"omnitrix":  return OMNI_EXTRA_PLIES
		"candytech": return CANDY_EXTRA_PLIES
	return 0

## Negamax material exchange: the net enemy-material the `attacker` can win from
## this position, choosing the line that maximises net AFTER the `defender`'s best
## recapture (which itself recurses `plies` deeper). Captures are single-drone
## chains within `reach`; the attacker may always decline (net 0), so a capture
## that loses material to a recapture is never counted as a threat. Bounded by how
## few drones can actually capture in a position — usually 0-3 — so it stays cheap.
func _deep_exchange_value(board: Node2D, attacker: Dictionary, defender: Dictionary,
						  reach: int, plies: int) -> float:
	var best_net: float = 0.0
	for start in attacker:
		var chain: Array = _capture_chain_from(board, attacker, defender, start, reach, reach)
		if chain.is_empty():
			continue
		var st: Dictionary = _simulate_plan(attacker, defender, chain)
		var gain: float = float(st["captured_value"])
		if gain <= 0.0:
			continue
		var net: float = gain
		if plies > 0:
			## Defender now attacks back from the resulting position.
			net -= _deep_exchange_value(board, st["enemy"], st["my"], reach, plies - 1)
		if net > best_net:
			best_net = net
	return best_net

## Build a position->true set from a sid_map's keys.
func _pos_set(sid_map: Dictionary) -> Dictionary:
	var s: Dictionary = {}
	for p in sid_map: s[p] = true
	return s

## Apply a full-turn plan (array of step dicts) to COPIES of the drone maps and
## report the resulting state + total enemy material captured. Pure simulation —
## touches no board state. "rotate" steps don't move drones; "move" steps with
## captured=true remove the enemy drone standing on the destination square.
## `target_value[pos]` overrides an enemy's captured value (raw _piece_value +
## revenge bonus); `priority_set[pos]` marks enemies whose capture earns the
## priority-take bonus. Both default empty (raw values, no priority).
func _simulate_plan(my_sid_map: Dictionary, enemy_sid_map: Dictionary, plan: Array,
					target_value: Dictionary = {}, priority_set: Dictionary = {}) -> Dictionary:
	var my: Dictionary = my_sid_map.duplicate()
	var enemy: Dictionary = enemy_sid_map.duplicate()
	## rot[pos] = rotation offset (0-5, in 60-degree steps) of the drone now at
	## `pos`, accumulated across this plan. Tracked so _board_control reflects a
	## drone's ROTATED move pattern after a rotate step (Extra-Hard).
	var rot: Dictionary = {}
	var captured_value: float = 0.0
	var captured_count: int = 0
	var priority_captures: int = 0
	## Material each double-line drone (sid) captures this plan, for the
	## favorable-trade rule in _eval_endstate.
	var dl_captured: Dictionary = {}
	for step in plan:
		if step.get("type", "") == "rotate":
			var at: Vector2i = step["at"]
			var steps: int = int(round(float(step.get("degrees", 0.0)) / 60.0)) % 6
			rot[at] = (int(rot.get(at, 0)) + steps) % 6
			continue
		var frm: Vector2i = step["from"]
		var to: Vector2i  = step["to"]
		if not my.has(frm):
			continue   ## defensive: plan desynced from state
		var sid: int = my[frm]
		my.erase(frm)
		my[to] = sid
		## Carry the drone's rotation along with it as it moves.
		var carried: int = int(rot.get(frm, 0))
		rot.erase(frm)
		if carried != 0:
			rot[to] = carried
		if step.get("captured", false) and enemy.has(to):
			## Effective capture value = raw material (+ revenge bonus via target_value).
			var cv: float = float(target_value.get(to, _piece_value(enemy[to])))
			captured_value += cv
			captured_count += 1
			if priority_set.has(to):
				priority_captures += 1
			if DOUBLE_LINE_SIDS.has(sid):
				dl_captured[sid] = float(dl_captured.get(sid, 0.0)) + cv
			enemy.erase(to)
	return {"my": my, "enemy": enemy, "captured_value": captured_value,
			"captured_count": captured_count, "priority_captures": priority_captures,
			"rot": rot, "dl_captured": dl_captured}

## HYBRID 1-ply opponent reply. Assuming the opponent rolls their max realistic
## roll (ASSUMED_HUMAN_ROLL), how many of OUR drones can they capture next turn,
## and what is the most valuable one they could take? Reach is capped at the
## perception horizon, so a low-difficulty bot is blind to far threats. Returns
## {count, worst_value}. count drives cardinal rule #2 (never expose >1 drone).
func _opponent_reply(board: Node2D, my: Dictionary, enemy: Dictionary, horizon: int) -> Dictionary:
	var reach: int = mini(horizon, ASSUMED_HUMAN_ROLL)
	var enemy_set: Dictionary = _pos_set(enemy)
	var count: int = 0
	var worst_value: float = 0.0
	for mypos in my:
		var target: Dictionary = {mypos: true}
		var threatened: bool = false
		for epos in enemy:
			var esid: int = enemy[epos]
			## Walls = other enemies + our other drones (can't pass through them,
			## but landing on mypos is the capture, so mypos itself stays open).
			var blocked: Dictionary = enemy_set.duplicate()
			blocked.erase(epos)
			for mp in my:
				if mp != mypos: blocked[mp] = true
			if _bfs_dist(board, epos, esid, blocked, target) <= reach:
				threatened = true
				break
		if threatened:
			count += 1
			worst_value = maxf(worst_value, _piece_value(my[mypos]))
	## Omni Trix: replace the 1-ply worst-value estimate with the net material the
	## opponent can actually win over a deeper exchange (their capture − our
	## recapture − their follow-up). A recapturable exposure nets ~0 and stops
	## scaring it; a genuine multi-ply losing trade nets high and it avoids it.
	var plies: int = _extra_reply_plies()
	if plies > 0 and count > 0:
		worst_value = _deep_exchange_value(board, enemy, my, reach, plies)
	return {"count": count, "worst_value": worst_value}

## Total distinct squares our drones can move to in one hop — a cheap proxy for
## board control / coverage (Extra-Hard only). Each drone is evaluated at its
## simulated rotation (rot[pos]), so rotating a drone into a wider move pattern
## genuinely raises this score. get_valid_move_coords_for_rotated already returns
## only on-board legal squares, so no extra is_valid_move filter is needed.
func _board_control(my: Dictionary, rot: Dictionary) -> int:
	var occupied: Dictionary = _pos_set(my)
	var reachable: Dictionary = {}
	for pos in my:
		for to in _cached_moves_rotated(pos, my[pos], int(rot.get(pos, 0))):
			if not occupied.has(to):
				reachable[to] = true
	return reachable.size()

## Best number of captures achievable from this position within `budget` moves,
## across single-drone chains and multi-drone direct captures. Used for the
## patience heuristic (compare a low current roll vs a potential roll of 5).
func _max_capture_count(board: Node2D, my: Dictionary, enemy: Dictionary, budget: int) -> int:
	var best: int = 0
	var direct: Array = _find_direct_captures(board, my, enemy)
	best = maxi(best, mini(direct.size(), budget))   ## one point per direct capture
	for start_pos in my:
		var chain: Array = _capture_chain_from(board, my, enemy, start_pos, budget, budget)
		var c: int = 0
		for s in chain:
			if String(s.get("type", "")) != "rotate" and bool(s.get("captured", false)):
				c += 1
		best = maxi(best, c)
	return best

## ── Skynet (Successor of Man) ──────────────────────────────────────────────
## Never retreats: a threatened drone is reinforced by another, or — if it is
## already defended — its attacker is taken. Repositioning to safety is replaced
## entirely by this unified-force response (and the safe-distance reposition
## candidate is suppressed for Skynet in _generate_candidates).
const SKYNET_DEFEND_DIST := 3   ## a drone is "defended" if a friendly can recapture within this many chains

## My drone positions an enemy can capture within `reach` chains.
func _skynet_threatened(board: Node2D, my: Dictionary, enemy: Dictionary, reach: int) -> Array:
	var out: Array = []
	var enemy_set: Dictionary = _pos_set(enemy)
	for mypos in my:
		for epos in enemy:
			var blocked: Dictionary = enemy_set.duplicate()
			blocked.erase(epos)
			for mp2 in my:
				if mp2 != mypos: blocked[mp2] = true
			if _bfs_dist(board, epos, enemy[epos], blocked, {mypos: true}) <= reach:
				out.append(mypos)
				break
	return out

## Is `pos` defended — can a friendly (other than the drone on it) recapture pos
## within SKYNET_DEFEND_DIST chains if an enemy lands there?
func _skynet_defended(board: Node2D, pos: Vector2i, my: Dictionary, enemy: Dictionary) -> bool:
	var occ: Dictionary = {}
	for ep in enemy: occ[ep] = true
	for p in my:
		if p != pos: occ[p] = true
	for f in my:
		if f == pos: continue
		var blocked: Dictionary = occ.duplicate()
		blocked.erase(f)
		if _bfs_dist(board, f, my[f], blocked, {pos: true}) <= SKYNET_DEFEND_DIST:
			return true
	return false

## Capture an enemy that threatens `T`: find the most valuable threatening enemy
## a friendly can reach within `budget` and return that capture plan. [] if none.
func _skynet_take_threat(board: Node2D, my: Dictionary, enemy: Dictionary, T: Vector2i, reach: int, budget: int) -> Array:
	var threats: Array = []
	var enemy_set: Dictionary = _pos_set(enemy)
	for epos in enemy:
		var blocked: Dictionary = enemy_set.duplicate()
		blocked.erase(epos)
		for mp2 in my:
			if mp2 != T: blocked[mp2] = true
		if _bfs_dist(board, epos, enemy[epos], blocked, {T: true}) <= reach:
			threats.append(epos)
	if threats.is_empty():
		return []
	threats.sort_custom(func(a, b): return _piece_value(enemy[a]) > _piece_value(enemy[b]))
	for e_pos in threats:
		for f in my:
			## Walls = our other drones + every enemy except the one being captured.
			var blk: Dictionary = {}
			for p in my:
				if p != f: blk[p] = true
			for e2 in enemy:
				if e2 != e_pos: blk[e2] = true
			var path: Array = _bfs_path(board, f, my[f], blk, {e_pos: true}, budget)
			if path.is_empty():
				continue
			var plan: Array = []
			var cur: Vector2i = f
			for i in path.size():
				plan.append({"type": "move", "from": cur, "to": path[i], "captured": i == path.size() - 1})
				cur = path[i]
			return plan
	return []

## Move another drone toward `T` so it can defend (recapture) it — the nearest
## eligible friendly is advanced until it is within SKYNET_DEFEND_DIST chains of T.
## [] if no reinforcement can close in this turn.
func _skynet_defender_move(board: Node2D, my: Dictionary, enemy: Dictionary, T: Vector2i, budget: int) -> Array:
	if budget < 1:
		return []
	var occ: Dictionary = {}
	for p in my: occ[p] = true
	for ep in enemy: occ[ep] = true
	var best_plan: Array = []
	var best_len: int = 9999
	for f in my:
		if f == T or _cube_dist(f, T) <= SKYNET_DEFEND_DIST:
			continue   ## already close enough to support
		var blk: Dictionary = occ.duplicate()
		blk.erase(f)
		blk.erase(T)   ## T is the goal, not a wall
		var path: Array = _bfs_path(board, f, my[f], blk, {T: true}, budget + SKYNET_DEFEND_DIST)
		if path.is_empty():
			continue
		## Advance F along the path within budget, stopping once within DEFEND_DIST
		## of T and never landing on T itself.
		var plan: Array = []
		var cur: Vector2i = f
		for i in range(mini(path.size(), budget)):
			if path[i] == T:
				break
			plan.append({"type": "move", "from": cur, "to": path[i], "captured": false})
			cur = path[i]
			if _cube_dist(cur, T) <= SKYNET_DEFEND_DIST:
				break
		if plan.is_empty():
			continue
		if plan.size() < best_len:
			best_len = plan.size()
			best_plan = plan
	return best_plan

## Skynet's threat response: reinforce the most valuable threatened drone, or take
## its attacker if it is already defended. Returns [] (fall through to normal
## capture/advance play — never a retreat) when no drone is threatened or nothing
## can be done this turn.
func _skynet_threat_response(board: Node2D, my: Dictionary, enemy: Dictionary, budget: int) -> Array:
	var reach: int = mini(_perception_horizon(), ASSUMED_HUMAN_ROLL)
	var threatened: Array = _skynet_threatened(board, my, enemy, reach)
	if threatened.is_empty():
		return []
	var T: Vector2i = threatened[0]
	for p in threatened:
		if _piece_value(my[p]) > _piece_value(my[T]):
			T = p
	if _skynet_defended(board, T, my, enemy):
		return _skynet_take_threat(board, my, enemy, T, reach, budget)
	return _skynet_defender_move(board, my, enemy, T, budget)

## ── MicroBots (swarm cohesion) ─────────────────────────────────────────────
## Every drone must stay within MICROBOT_MAX_SPREAD movement chains of at least
## one friendly — the swarm never strays from the hive, captures included. Plans
## whose END state breaks cohesion get MICROBOT_COHESION_PENALTY, so a stray move
## is only ever taken when no cohesive option exists at all (never gets stuck).
const MICROBOT_MAX_SPREAD       := 5
const MICROBOT_COHESION_PENALTY := 100000.0

func _microbots_cohesion_ok(board: Node2D, my: Dictionary) -> bool:
	if my.size() < 2:
		return true   ## a lone drone has no hive to keep
	var my_set: Dictionary = _pos_set(my)
	for pos in my:
		var others: Dictionary = my_set.duplicate()
		others.erase(pos)
		## Friendlies are the targets (don't block them — _bfs_dist skips blocked
		## cells before the target check, so a blocked target reads as unreachable).
		if _bfs_dist(board, pos, my[pos], {}, others) > MICROBOT_MAX_SPREAD:
			return false
	return true

## ── Candy Tech (rotate toward the enemy) ───────────────────────────────────
## Rotation steps (1-5) whose rotated move pattern advances furthest toward
## `target`, or 0 if no rotation gets closer. Edge tiles only (caller checks).
func _best_rotation_steps_toward(board: Node2D, pos: Vector2i, sid: int, target: Vector2i) -> int:
	var cur_d: int = _cube_dist(pos, target)
	## Baseline = what the drone can already do at its CURRENT facing. A rotation is
	## only worth it if it STRICTLY beats this — otherwise an already-aligned drone
	## would re-rotate every positional turn and spin in place forever.
	var best_gain: int = 0
	for to in _cached_moves_rotated(pos, sid, 0):
		best_gain = maxi(best_gain, cur_d - _cube_dist(to, target))
	var best_steps: int = 0
	for steps in [1, 2, 3, 4, 5]:
		var gain: int = 0
		for to in _cached_moves_rotated(pos, sid, steps):
			gain = maxi(gain, cur_d - _cube_dist(to, target))
		if gain > best_gain:
			best_gain = gain
			best_steps = steps
	return best_steps

## Rotate `pos` in place toward the enemy, then spend the rest of the turn closing
## the OTHER drones in (the rotated drone holds, lined up for a next-turn take).
func _candytech_rot_plan(board: Node2D, my: Dictionary, enemy: Dictionary, pos: Vector2i, steps: int, movement_points: int) -> Array:
	var plan: Array = [{"type": "rotate", "at": pos, "degrees": float(steps) * 60.0}]
	if movement_points > 1:
		var others: Dictionary = my.duplicate()
		others.erase(pos)
		if not others.is_empty():
			plan.append_array(_reposition_steps(board, others, enemy, movement_points - 1, 1))
	return plan

## Candy Tech's positional move: rotate an edge drone toward the enemy. Priority is
## the nearest enemy when one is within CANDY_ROTATE_NEAR chains; otherwise rotate
## toward the enemy majority (centroid), even when the bulk is beyond the horizon.
const CANDY_ROTATE_NEAR := 4
func _candytech_rotation(board: Node2D, my: Dictionary, enemy: Dictionary, movement_points: int) -> Array:
	if movement_points < 1 or enemy.is_empty():
		return []
	var occ: Dictionary = {}
	for p in my: occ[p] = true
	for ep in enemy: occ[ep] = true
	## Priority: nearest enemy within CANDY_ROTATE_NEAR chains of an edge drone.
	var best_pos: Vector2i = Vector2i(-1, -1)
	var best_steps: int = 0
	var best_near: int = 9999
	for pos in my:
		if not board.is_edge_tile(pos):
			continue
		var sid: int = my[pos]
		var nd: int = 9999
		var nearest: Vector2i = Vector2i(-1, -1)
		for ep in enemy:
			var blk: Dictionary = occ.duplicate()
			blk.erase(pos); blk.erase(ep)
			var d: int = _bfs_dist(board, pos, sid, blk, {ep: true})
			if d < nd:
				nd = d; nearest = ep
		if nearest.x < 0 or nd >= CANDY_ROTATE_NEAR:
			continue
		if nd < best_near:
			var steps: int = _best_rotation_steps_toward(board, pos, sid, nearest)
			if steps > 0:
				best_near = nd; best_pos = pos; best_steps = steps
	if best_pos.x >= 0:
		return _candytech_rot_plan(board, my, enemy, best_pos, best_steps, movement_points)
	## Else: rotate the best edge drone toward the enemy centroid (the bulk).
	var cx: int = 0
	var cy: int = 0
	for ep in enemy:
		cx += ep.x; cy += ep.y
	var centroid: Vector2i = Vector2i(int(round(float(cx) / float(enemy.size()))), int(round(float(cy) / float(enemy.size()))))
	var best_improve: int = 0
	for pos in my:
		if not board.is_edge_tile(pos):
			continue
		var sid: int = my[pos]
		var cur_d: int = _cube_dist(pos, centroid)
		## Baseline at current facing — only rotate if a rotation STRICTLY improves
		## on it, so a drone that already faces the bulk stops rotating.
		var base_gain: int = 0
		for to in _cached_moves_rotated(pos, sid, 0):
			base_gain = maxi(base_gain, cur_d - _cube_dist(to, centroid))
		for steps in [1, 2, 3, 4, 5]:
			var gain: int = 0
			for to in _cached_moves_rotated(pos, sid, steps):
				gain = maxi(gain, cur_d - _cube_dist(to, centroid))
			if gain - base_gain > best_improve:
				best_improve = gain - base_gain; best_pos = pos; best_steps = steps
	if best_pos.x >= 0 and best_steps > 0:
		return _candytech_rot_plan(board, my, enemy, best_pos, best_steps, movement_points)
	return []

## Score a simulated end-state. Higher = better for the bot.
##   + material captured this turn
##   + safety: each drone resting within TARGET_DIST chains of a friendly
##   - opponent reply: material the opponent can capture next turn (hybrid term),
##     with a hard cliff if they can take more than one drone (cardinal rule #2)
##   + board control (Extra-Hard)
func _eval_endstate(board: Node2D, state: Dictionary, horizon: int, difficulty: int, brewing: bool, ahead: bool, late_game: bool) -> float:
	var my: Dictionary    = state["my"]
	var enemy: Dictionary = state["enemy"]
	## Material captured (revenge bonus already folded into captured_value) plus a
	## flat priority-take bonus per nearby (<3 chain) enemy taken.
	var score: float = state["captured_value"] * W_MATERIAL
	score += float(state.get("priority_captures", 0)) * PRIORITY_TAKE_BONUS

	## Double-line drones only capture on a favourable trade: captured material
	## must exceed their own value (or merely equal it when we're already ahead).
	for dlsid in state.get("dl_captured", {}):
		var captured: float = state["dl_captured"][dlsid]
		var own: float = _piece_value(dlsid)
		if not (captured > own or (captured == own and ahead)):
			score -= FORBID_DL_TRADE

	## Winning the game (all enemy drones gone) dominates everything.
	if enemy.is_empty():
		return 1_000_000.0 + score

	## Safety: reward each drone that rests within TARGET_DIST chains of a
	## friendly drone (mutual support). Uses chain distance, not grid distance.
	var my_set: Dictionary = _pos_set(my)
	if my.size() >= 2:
		for mypos in my:
			var sid: int = my[mypos]
			var friends: Dictionary = my_set.duplicate()
			friends.erase(mypos)
			if _bfs_dist(board, mypos, sid, friends, friends) <= TARGET_DIST:
				score += W_SAFETY

	## Hybrid opponent-reply penalty (cardinal rule #2). Caution scales by
	## difficulty — Easy is bolder (commits to captures even at some risk) — and is
	## amplified in the endgame, where losing any drone is often game-deciding, so
	## the bot guards its pieces much harder.
	var caution: float = EXPOSE_CAUTION[clampi(difficulty, 0, 3)]
	if late_game:
		caution *= ENDGAME_EXPOSE_MULT
	var reply: Dictionary = _opponent_reply(board, my, enemy, horizon)
	score -= reply["worst_value"] * W_EXPOSE * caution
	if reply["count"] >= 2:
		score -= (PENALTY_EXPOSE_2 + float(reply["count"]) * W_EXPOSE) * caution

	## Board control (Extra-Hard) — distinct squares our drones can reach.
	if difficulty >= 3:
		score += float(_board_control(my, state.get("rot", {}))) * W_CONTROL

	## Hard+: patience. When a multi-capture is brewing but THIS roll is too low
	## to land it, don't burn the setup on a small DEFENDED capture (a trade that
	## also exposes us) — prefer pressuring elsewhere and rolling again next turn.
	## A free/undefended capture (reply count 0) is never penalised.
	if brewing and difficulty >= 2:
		if int(state.get("captured_count", 0)) == 1 and reply["count"] >= 1:
			score -= PATIENCE_PENALTY

	return score

func _plan_turn(board: Node2D, my_sid_map: Dictionary,
				enemy_sid_map: Dictionary, movement_points: int) -> Array:
	if game_manager.active_bot_profile_id == "bey":
		return _plan_turn_bey(board, my_sid_map, enemy_sid_map, movement_points)
	## CLU positions to hold in place during normal play (formation lock).
	var clu_locked: Dictionary = {}
	## CLU's signature opening replaces the 13/14 rotation: send tile 15 to (8,5),
	## then slide tile 16 into the spot it vacated. Falls through to normal play
	## once tile 15 is in place.
	if game_manager.active_bot_profile_id == "clu":
		var clu_open: Array = _clu_opening_plan(board, my_sid_map, movement_points)
		if not clu_open.is_empty():
			return clu_open
		## Formation: while early-game-and-safe and no multi-capture is available,
		## shepherd double-line drones onto column 9 and then hold the formation.
		var multi_cap: bool = _max_capture_count(board, my_sid_map, enemy_sid_map, movement_points) >= 2
		if not multi_cap and _clu_formation_active(board, my_sid_map, enemy_sid_map):
			var form_move: Array = _clu_form_move(board, my_sid_map, enemy_sid_map, movement_points)
			if not form_move.is_empty():
				return form_move
			clu_locked = _clu_locked_set(board, my_sid_map, enemy_sid_map)
	elif game_manager.active_bot_profile_id == "microbots":
		pass   ## MicroBots skip the 13/14 opening rotation entirely
	else:
		## Opening rotation: set 13/14 to their preferred orientation before
		## anything else (one rotation per call; only fires at spawn rotation).
		var opening: Array = _opening_rotation_plan(board, my_sid_map, movement_points)
		if not opening.is_empty():
			return opening
	## Round 59 — candidate-generation + hybrid evaluation. Generate a diverse
	## set of full-turn plans (dives, pokes, advances, repositions), simulate
	## each, and keep the one the evaluator scores highest. Poke-vs-dive and
	## "always take an undefended drone" emerge from the eval (captured material
	## vs the opponent-reply penalty), not from a fixed priority ladder.
	var difficulty: int = game_manager._current_bot_difficulty()
	var horizon: int    = _perception_horizon()
	var candidates: Array = _generate_candidates(board, my_sid_map, enemy_sid_map, movement_points, horizon, difficulty)

	## Endgame: with few drones left, patience is suspended (take now to close out)
	## and exposure is weighted harder (every loss is decisive).
	var late_game: bool = my_sid_map.size() + enemy_sid_map.size() <= LATE_GAME_PIECES

	## Patience (Hard+, NOT endgame): is a multi-capture brewing that this roll
	## can't land but a max roll could? If so, the eval discourages spending the
	## setup on a small defended capture now.
	var brewing: bool = false
	if difficulty >= 2 and not late_game:
		brewing = _max_capture_count(board, my_sid_map, enemy_sid_map, ASSUMED_HUMAN_ROLL) >= 2 \
			and _max_capture_count(board, my_sid_map, enemy_sid_map, movement_points) < 2

	## Are we ahead in total material right now? (Lets double-line drones take
	## break-even trades — see the DOUBLE_LINE_SIDS rule in _eval_endstate.)
	var ahead: bool = _total_material(my_sid_map) > _total_material(enemy_sid_map)

	## Take incentives: revenge targets (enemies that took our drones last turn)
	## are worth +REVENGE_VALUE_BONUS material; enemies within PRIORITY_TAKE_RANGE
	## chains of one of our drones earn the priority-take bonus when captured.
	var target_value: Dictionary = {}
	for epos in enemy_sid_map:
		var esid: int = enemy_sid_map[epos]
		if int(_revenge.get(esid, 0)) > 0:
			target_value[epos] = _piece_value(esid) + REVENGE_VALUE_BONUS
	var priority_set: Dictionary = {}
	for epos in enemy_sid_map:
		for mpos in my_sid_map:
			var msid: int = my_sid_map[mpos]
			var blocked: Dictionary = {}
			for p in my_sid_map:
				if p != mpos: blocked[p] = true
			for ep in enemy_sid_map:
				if ep != epos: blocked[ep] = true
			if _bfs_dist(board, mpos, msid, blocked, {epos: true}) < PRIORITY_TAKE_RANGE:
				priority_set[epos] = true
				break

	var best_plan: Array  = []
	var best_score: float = -INF
	var best_captured: int = 0
	for plan in candidates:
		if plan.is_empty(): continue
		if _plan_moves_locked(plan, clu_locked): continue   ## CLU holds its formation
		var state: Dictionary = _simulate_plan(my_sid_map, enemy_sid_map, plan, target_value, priority_set)
		var score: float = _eval_endstate(board, state, horizon, difficulty, brewing, ahead, late_game)
		## MicroBots: keep the swarm cohesive — a plan that strands a drone more than
		## MICROBOT_MAX_SPREAD chains from every friendly is heavily penalised (applies
		## to captures too).
		if game_manager.active_bot_profile_id == "microbots" and not _microbots_cohesion_ok(board, state["my"]):
			score -= MICROBOT_COHESION_PENALTY
		## Easy plays loose: heavy score noise so it makes beatable mistakes.
		if difficulty == 0:
			score += _rng.randf_range(-EASY_NOISE, EASY_NOISE)
		if score > best_score:
			best_score = score
			best_plan  = plan
			best_captured = int(state.get("captured_count", 0))

	## Skynet: it never retreats and prizes a unified force. Its full tactical eval
	## above is untouched — but on a PURELY POSITIONAL turn (the best play captures
	## nothing) it reinforces a threatened drone, or eliminates the attacker if that
	## drone is already defended, instead of just repositioning.
	if game_manager.active_bot_profile_id == "skynet" and best_captured == 0:
		var sky: Array = _skynet_threat_response(board, my_sid_map, enemy_sid_map, movement_points)
		if not sky.is_empty():
			return sky

	## Candy Tech: on a positional turn (no capture taken), rotate an edge drone
	## toward the enemy — the nearest within reach, else the majority centroid —
	## instead of just repositioning.
	if game_manager.active_bot_profile_id == "candytech" and best_captured == 0:
		var crot: Array = _candytech_rotation(board, my_sid_map, enemy_sid_map, movement_points)
		if not crot.is_empty():
			return crot

	return best_plan

## Returns a single rotate step that moves a 13/14 toward its preferred opening
## orientation (OPENING_ROTATION), or [] when both are already oriented. Only
## fires while the drone is still at spawn rotation (_rot_step == 0) and on its
## rotatable edge tile, so in practice this runs only on the bot's first turn.
func _opening_rotation_plan(board: Node2D, my_sid_map: Dictionary, movement_points: int) -> Array:
	if movement_points < 1:
		return []
	for pos in my_sid_map:
		var sid: int = my_sid_map[pos]
		if not OPENING_ROTATION.has(sid):
			continue
		if board._rot_step(sid) != 0 or not board.is_edge_tile(pos):
			continue
		return [{"type": "rotate", "at": pos, "degrees": float(OPENING_ROTATION[sid])}]
	return []

## CLU's scripted opening: path tile 15 to CLU_OPENING_TARGET, then slide tile 16
## into the square tile 15 vacated. Returns [] once tile 15 is in place (or can't
## reach it this turn), so normal play resumes after the opening.
const CLU_OPENING_TARGET := Vector2i(8, 5)
func _clu_opening_plan(board: Node2D, my_sid_map: Dictionary, movement_points: int) -> Array:
	if movement_points < 1:
		return []
	var pos15: Vector2i = Vector2i(-999, -999)
	var pos16: Vector2i = Vector2i(-999, -999)
	for p in my_sid_map:
		if my_sid_map[p] == 15: pos15 = p
		elif my_sid_map[p] == 16: pos16 = p
	if pos15 == Vector2i(-999, -999) or pos15 == CLU_OPENING_TARGET:
		return []   ## no tile 15, or it's already placed — opening complete
	## Path tile 15 to the target, routing around our own drones.
	var blk15: Dictionary = {}
	for p in my_sid_map:
		if p != pos15: blk15[p] = true
	var path15: Array = _bfs_path(board, pos15, 15, blk15, {CLU_OPENING_TARGET: true}, movement_points)
	if path15.is_empty():
		return []   ## not reachable this roll — fall back to normal play
	var plan: Array = []
	var cur: Vector2i = pos15
	for nxt in path15:
		plan.append({"type": "move", "from": cur, "to": nxt, "captured": false})
		cur = nxt
	## Slide tile 16 into tile 15's vacated spot if there's movement left and it
	## can reach (tile 16 teleports, so the spot must be a valid destination).
	var remaining: int = movement_points - path15.size()
	if remaining > 0 and pos16 != Vector2i(-999, -999):
		var blk16: Dictionary = {}
		for p in my_sid_map:
			if p != pos16: blk16[p] = true
		blk16.erase(pos15)            ## 15's old square is now open
		blk16[CLU_OPENING_TARGET] = true   ## 15 now occupies the target
		var path16: Array = _bfs_path(board, pos16, 16, blk16, {pos15: true}, remaining)
		var c2: Vector2i = pos16
		for nxt in path16:
			plan.append({"type": "move", "from": c2, "to": nxt, "captured": false})
			c2 = nxt
	return plan

## ── CLU formation ─────────────────────────────────────────────────────────
## In the early game while not greatly threatened, CLU shepherds its double-line
## drones onto column CLU_FORMATION_COL and then holds them there (locked) until a
## drone is threatened within CLU_THREAT_UNLOCK chains or a multi-capture is on.
## Tile 15 is excluded (the opening parks it at CLU_OPENING_TARGET); 16 is its
## opener. Those two are held in place too.
const CLU_FORMATION_COL    := 9
const CLU_FORMATION_SIDS    := [21, 17, 22]   ## CLU's double-line drones, minus 15 (opener)
const CLU_THREAT_NEAR       := 3              ## "greatly threatened" radius (chains)
const CLU_THREAT_UNLOCK     := 5              ## a held drone unlocks if an enemy is this close

## True if some enemy can reach `pos` within `n` movement chains.
func _threatened_within(board: Node2D, pos: Vector2i, my_sid_map: Dictionary, enemy_sid_map: Dictionary, n: int) -> bool:
	for ep in enemy_sid_map:
		var esid: int = enemy_sid_map[ep]
		var blocked: Dictionary = {}
		for e2 in enemy_sid_map:
			if e2 != ep: blocked[e2] = true
		for mp2 in my_sid_map:
			if mp2 != pos: blocked[mp2] = true
		if _bfs_dist(board, ep, esid, blocked, {pos: true}) < n:
			return true
	return false

## Early game (neither side has lost > 3 drones) AND no enemy within CLU_THREAT_NEAR
## chains of any CLU drone — the window in which CLU forms up.
func _clu_formation_active(board: Node2D, my_sid_map: Dictionary, enemy_sid_map: Dictionary) -> bool:
	var start: Dictionary = board._starting_piece_count
	var s_me: int = int(start.get(2, 0))
	var s_op: int = int(start.get(1, 0))
	if s_me <= 0 or s_op <= 0:
		return false
	if (s_me - my_sid_map.size()) > 3 or (s_op - enemy_sid_map.size()) > 3:
		return false
	for pos in my_sid_map:
		if _threatened_within(board, pos, my_sid_map, enemy_sid_map, CLU_THREAT_NEAR):
			return false
	return true

## Move one not-yet-formed double-line drone toward a free cell on column 9.
func _clu_form_move(board: Node2D, my_sid_map: Dictionary, enemy_sid_map: Dictionary, movement_points: int) -> Array:
	if movement_points < 1:
		return []
	var occ: Dictionary = {}
	for p in my_sid_map: occ[p] = true
	for ep in enemy_sid_map: occ[ep] = true
	for pos in my_sid_map:
		var sid: int = my_sid_map[pos]
		if not CLU_FORMATION_SIDS.has(sid) or pos.x == CLU_FORMATION_COL:
			continue
		var targets: Dictionary = {}
		for y in range(0, 12):
			var c: Vector2i = Vector2i(CLU_FORMATION_COL, y)
			if board._is_board_cell(c) and not occ.has(c):
				targets[c] = true
		if targets.is_empty():
			continue
		var blk: Dictionary = occ.duplicate()
		blk.erase(pos)
		var path: Array = _bfs_path(board, pos, sid, blk, targets, movement_points)
		if path.is_empty():
			continue
		var plan: Array = []
		var cur: Vector2i = pos
		for nxt in path:
			plan.append({"type": "move", "from": cur, "to": nxt, "captured": false})
			cur = nxt
		return plan   ## one formation drone per turn
	return []

## Positions CLU should NOT move during normal play: formed double-line drones on
## column 9, plus the opening pieces (15 at the target, 16), unless that drone is
## threatened within CLU_THREAT_UNLOCK chains.
func _clu_locked_set(board: Node2D, my_sid_map: Dictionary, enemy_sid_map: Dictionary) -> Dictionary:
	var locked: Dictionary = {}
	for pos in my_sid_map:
		var sid: int = my_sid_map[pos]
		var is_formed: bool  = CLU_FORMATION_SIDS.has(sid) and pos.x == CLU_FORMATION_COL
		var is_opener: bool  = (sid == 15 and pos == CLU_OPENING_TARGET) or sid == 16
		if not (is_formed or is_opener):
			continue
		if _threatened_within(board, pos, my_sid_map, enemy_sid_map, CLU_THREAT_UNLOCK):
			continue   ## threatened — free to move
		locked[pos] = true
	return locked

## True if any move step in `plan` moves a locked drone.
func _plan_moves_locked(plan: Array, locked: Dictionary) -> bool:
	if locked.is_empty():
		return false
	for step in plan:
		if String(step.get("type", "")) != "rotate" and locked.has(step.get("from")):
			return true
	return false

## Generate a diverse set of candidate full-turn plans for the hybrid evaluator
## to choose between. Each is a valid step-dict plan spending <= movement_points,
## reusing the trusted plan generators as candidate sources.
func _generate_candidates(board: Node2D, my_sid_map: Dictionary,
						   enemy_sid_map: Dictionary, movement_points: int,
						   horizon: int, difficulty: int) -> Array:
	var cands: Array = []
	var captures: Array = _find_direct_captures(board, my_sid_map, enemy_sid_map)

	## Dive: chain as many direct captures as the budget allows.
	if captures.size() >= 2:
		cands.append(_plan_multi_capture(captures, movement_points))

	## Single-drone capture chains: each drone captures, then keeps capturing
	## from its NEW position with whatever movement is left — same drone first.
	## The FIRST capture is perception-gated (Easy reacts within `horizon`), but
	## follow-up captures are free: once a drone has committed forward, it should
	## spend the rest of its movement taking more value rather than stopping.
	for start_pos in my_sid_map:
		var chain: Array = _capture_chain_from(board, my_sid_map, enemy_sid_map, start_pos, movement_points, horizon)
		if not chain.is_empty():
			cands.append(chain)

	## Poke / single capture: capture then retreat (two retreat styles).
	for cap in captures:
		cands.append(_bey_poke(board, cap, my_sid_map, enemy_sid_map, movement_points))
		cands.append(_plan_capture_then_reposition(board, cap, my_sid_map, enemy_sid_map, movement_points))

	## Advance toward a reachable enemy and capture on arrival — only if that
	## capture lands within the perception horizon (Easy ignores far targets).
	var adv: Array = _plan_advance_and_capture(board, my_sid_map, enemy_sid_map, movement_points)
	if not adv.is_empty() and _first_capture_chain(adv) <= horizon:
		cands.append(adv)

	## Pure positional plans: rest at safe distance, or close in toward enemies.
	## Skynet never retreats — its safe-distance "rest" candidate is suppressed so
	## it only ever holds position or advances (its defensive play is reinforcement,
	## handled in _plan_turn, not falling back).
	if game_manager.active_bot_profile_id != "skynet":
		cands.append(_reposition_steps(board, my_sid_map, enemy_sid_map, movement_points, TARGET_DIST))
	cands.append(_reposition_steps(board, my_sid_map, enemy_sid_map, movement_points, 1))

	## Late game: drones on rotation tiles may rotate tactically to reach captures.
	if my_sid_map.size() + enemy_sid_map.size() <= LATE_GAME_PIECES:
		cands.append_array(_late_game_rotation_candidates(board, my_sid_map, enemy_sid_map, movement_points))

	## Extra-Hard signature: rotate drones on rotation tiles to widen board control
	## — but NOT in the endgame, where takes and defence matter more than coverage.
	if difficulty >= 3 and my_sid_map.size() + enemy_sid_map.size() > LATE_GAME_PIECES:
		cands.append_array(_board_control_rotation_candidates(board, my_sid_map, enemy_sid_map, movement_points))

	return cands

## Extra-Hard only — rotate a drone on a rotation tile to an orientation that may
## widen the squad's coverage, then spend the rest of the budget repositioning the
## others. The board-control term in _eval_endstate keeps the result only if the
## extra coverage is worth the movement point. Skips 13/14 (they keep their fixed
## opening orientation until the late game) and double-line drones (whose
## orientation is governed by the trade rule, not coverage).
func _board_control_rotation_candidates(board: Node2D, my_sid_map: Dictionary,
										enemy_sid_map: Dictionary, movement_points: int) -> Array:
	var cands: Array = []
	if movement_points < 1:
		return cands
	for pos in my_sid_map:
		var sid: int = my_sid_map[pos]
		if OPENING_ROTATION.has(sid) or DOUBLE_LINE_SIDS.has(sid):
			continue
		if not board.is_edge_tile(pos):
			continue
		for steps in [1, 2, 3, 4, 5]:
			var plan: Array = [{"type": "rotate", "at": pos, "degrees": float(steps) * 60.0}]
			if movement_points > 1:
				var others: Dictionary = my_sid_map.duplicate()
				others.erase(pos)
				if not others.is_empty():
					plan.append_array(_reposition_steps(board, others, enemy_sid_map, movement_points - 1, TARGET_DIST))
			cands.append(plan)
	return cands

## Late game only (total drones <= LATE_GAME_PIECES): the fixed opening orientation
## is dropped. For each drone on a rotatable edge tile, try rotating to each facing
## and run a capture chain in it; the eval keeps the result only if the rotated
## capture beats the un-rotated options (it costs a movement point to rotate). This
## is how a 13/14 can line up a late-game take its 60/300 facing couldn't reach.
func _late_game_rotation_candidates(board: Node2D, my_sid_map: Dictionary,
									enemy_sid_map: Dictionary, movement_points: int) -> Array:
	var cands: Array = []
	if movement_points < 2 or enemy_sid_map.is_empty():
		return cands
	for pos in my_sid_map:
		if not board.is_edge_tile(pos):
			continue
		for steps in [1, 2, 3, 4, 5]:
			var chain: Array = _capture_chain_from(board, my_sid_map, enemy_sid_map, pos, movement_points - 1, movement_points - 1, steps)
			if chain.is_empty():
				continue
			var plan: Array = [{"type": "rotate", "at": pos, "degrees": float(steps) * 60.0}]
			plan.append_array(chain)
			cands.append(plan)
	return cands

## Greedy single-drone capture chain starting at `start`. Repeatedly BFS-paths
## to the most valuable still-reachable enemy and captures it, continuing from
## the drone's new square until no enemy is reachable or movement runs out.
## The FIRST capture must be reachable within `first_horizon` chains (perception
## gating — Easy ignores far targets); every follow-up capture is limited only by
## the movement left, so a drone that has committed forward keeps taking value.
## `rot` = rotation offset the drone moves at for the whole chain (default 0 =
## current facing). A weak-side drone that rotated strong-side-forward on its edge
## then captures along that orientation passes its rotation here.
## Hard bound on the number of chains the search explores, so a crowded board
## can't blow up the per-turn cost. Falls back to the best chain found so far.
const BCC_NODE_CAP := 400

## Best single-drone capture chain from `start`: the capture sequence that
## maximises TOTAL captured material within `budget`. A greedy highest-value-first
## walk grabs one fat target and can miss a same-length route that takes more
## material overall (e.g. 6+6 beats a lone 8), so this is a bounded depth-first
## search over capture orders. The first capture must fall within `first_horizon`
## chains (perception gating); later captures use the remaining budget. Other
## friendly drones are walls; enemies not being captured this leg are walls too.
func _capture_chain_from(board: Node2D, my_sid_map: Dictionary, enemy_sid_map: Dictionary,
						 start: Vector2i, budget: int, first_horizon: int, rot: int = 0) -> Array:
	var sid: int = my_sid_map[start]
	var other_my: Dictionary = {}   ## our other drones act as walls
	for p in my_sid_map:
		if p != start: other_my[p] = true
	var counter: Array = [0]        ## by-ref node budget shared across recursion
	var best: Dictionary = _bcc_search(board, sid, start, budget, first_horizon,
		enemy_sid_map.duplicate(), other_my, rot, true, counter)
	return best["plan"]

## Recursive helper for _capture_chain_from. Returns {"value": total material,
## "plan": Array of move steps} for the richest chain reachable from `cur`.
func _bcc_search(board: Node2D, sid: int, cur: Vector2i, budget: int, first_horizon: int,
				 remaining_enemy: Dictionary, other_my: Dictionary, rot: int,
				 first: bool, counter: Array) -> Dictionary:
	var best: Dictionary = {"value": 0.0, "plan": []}
	if budget <= 0 or remaining_enemy.is_empty() or counter[0] >= BCC_NODE_CAP:
		return best
	var reach: int = mini(budget, first_horizon) if first else budget
	for ep in remaining_enemy:
		if counter[0] >= BCC_NODE_CAP:
			break
		counter[0] += 1
		## All enemies except the target are walls (can't pass through them).
		var blocked: Dictionary = other_my.duplicate()
		for e2 in remaining_enemy:
			if e2 != ep: blocked[e2] = true
		var path: Array = _bfs_path(board, cur, sid, blocked, {ep: true}, reach, rot)
		if path.is_empty():
			continue
		var leg: Array = []
		var c: Vector2i = cur
		for i in path.size():
			leg.append({"type": "move", "from": c, "to": path[i], "captured": i == path.size() - 1})
			c = path[i]
		var rem2: Dictionary = remaining_enemy.duplicate()
		rem2.erase(ep)
		## Continue the chain from the captured square with the remaining budget.
		var sub: Dictionary = _bcc_search(board, sid, ep, budget - path.size(), first_horizon,
			rem2, other_my, rot, false, counter)
		var total: float = _piece_value(remaining_enemy[ep]) + float(sub["value"])
		var plan: Array  = leg + sub["plan"]
		if total > best["value"] or (total == best["value"] and total > 0.0 and plan.size() < best["plan"].size()):
			best = {"value": total, "plan": plan}
	return best

## 1-based chain-link index of the first capturing step in a plan, or a large
## sentinel if the plan captures nothing. Used for perception-horizon gating.
func _first_capture_chain(plan: Array) -> int:
	var link: int = 0
	for step in plan:
		link += 1
		if step.get("type", "") != "rotate" and step.get("captured", false):
			return link
	return MAX_DIST + 99

## -- Bey (Master of the Rotating Blade) -----------------------------------
## Hard-mode base. Dives (multi-capture) twice as often. Single captures are
## pokes: capture then retreat back toward origin or to an edge tile.
## When nothing to capture, moves non-edge pieces to edge tiles first.

## Capture then retreat: move the capturing piece to be 3 movement chains
## from any remaining enemy. Each hop picks the move that maximises distance
## to the nearest enemy (capped at TARGET_DIST=3 — once safe, stay safe).
func _bey_poke(board: Node2D, cap: Dictionary, my_sid_map: Dictionary, enemy_sid_map: Dictionary, movement_points: int) -> Array:
	var from_pos: Vector2i = cap["from"]
	var to_pos: Vector2i   = cap["to"]
	var sid: int           = my_sid_map[from_pos]
	var plan: Array = [{"type": "move", "from": from_pos, "to": to_pos, "captured": true}]
	var remaining: int = movement_points - 1
	if remaining <= 0:
		return plan
	var new_enemy: Dictionary = enemy_sid_map.duplicate()
	new_enemy.erase(to_pos)
	var enemy_targets: Dictionary = {}
	for p in new_enemy: enemy_targets[p] = true
	## Occupied: all friendlies + remaining enemies, piece moved from→to
	var occ: Dictionary = {}
	for p in my_sid_map: occ[p] = true
	for p in new_enemy:  occ[p] = true
	occ.erase(from_pos)
	var cur: Vector2i = to_pos
	for _i in range(remaining):
		occ.erase(cur)
		var best: Vector2i     = Vector2i(-1, -1)
		var best_score: float  = -INF
		var fallback: Vector2i = Vector2i(-1, -1)
		for nxt in _cached_moves_rotated(cur, sid, 0):
			if occ.has(nxt) or not board.is_valid_move(cur, nxt): continue
			if fallback == Vector2i(-1, -1): fallback = nxt
			var blk: Dictionary = occ.duplicate()
			var d: int   = _bfs_dist(board, nxt, sid, blk, enemy_targets)
			var score: float = float(d)
			if score > best_score:
				best_score = score; best = nxt
		var chosen: Vector2i = best if best != Vector2i(-1, -1) else fallback
		if chosen == Vector2i(-1, -1):
			occ[cur] = true; break
		plan.append({"type": "move", "from": cur, "to": chosen, "captured": false})
		occ[chosen] = true
		cur = chosen
	return plan

## Move the first non-edge piece toward an edge tile. Falls back to closing
## distance to 1 (ready to poke) when all pieces are already on edge tiles.
func _bey_reposition(board: Node2D, my_sid_map: Dictionary, enemy_sid_map: Dictionary, movement_points: int) -> Array:
	var all_blocked: Dictionary = {}
	for p in my_sid_map:     all_blocked[p] = true
	for ep in enemy_sid_map: all_blocked[ep] = true
	for from_pos in my_sid_map:
		if board.is_edge_tile(from_pos): continue
		var sid: int = my_sid_map[from_pos]
		var best_to: Vector2i = Vector2i(-1, -1)
		for to in _cached_moves_rotated(from_pos, sid, 0):
			if all_blocked.has(to) or not board.is_valid_move(from_pos, to): continue
			if board.is_edge_tile(to): best_to = to; break
			if best_to == Vector2i(-1, -1): best_to = to
		if best_to != Vector2i(-1, -1):
			var plan: Array = [{"type": "move", "from": from_pos, "to": best_to, "captured": false}]
			if movement_points > 1:
				var new_my: Dictionary = my_sid_map.duplicate()
				new_my.erase(from_pos); new_my[best_to] = sid
				plan.append_array(_reposition_steps(board, new_my, enemy_sid_map, movement_points - 1, 1))
			return plan
	## All on edge tiles — close in to distance 1 ready to poke
	return _reposition_steps(board, my_sid_map, enemy_sid_map, movement_points, 1)

## Cube (hex) distance between two offset coords — matches HexBoard._hex_dist.
func _cube_dist(a: Vector2i, b: Vector2i) -> int:
	var aq: int = a.x - ((a.y - (a.y & 1)) >> 1)
	var bq: int = b.x - ((b.y - (b.y & 1)) >> 1)
	return (abs(aq - bq) + abs(a.y - b.y) + abs((-aq - a.y) - (-bq - b.y))) >> 1

## Retreat one drone (at `start`, facing rotation `rot`) away from enemies,
## maximising chain distance to the nearest each hop — bey's poke retreat after a
## rotation-enabled capture.
func _bey_retreat(board: Node2D, start: Vector2i, sid: int, rot: int,
				  my_sid_map: Dictionary, enemy_sid_map: Dictionary, budget: int) -> Array:
	var plan: Array = []
	if budget <= 0 or enemy_sid_map.is_empty():
		return plan
	var enemy_targets: Dictionary = _pos_set(enemy_sid_map)
	var occ: Dictionary = {}
	for p in my_sid_map: occ[p] = true
	for p in enemy_sid_map: occ[p] = true
	var cur: Vector2i = start
	for _i in range(budget):
		occ.erase(cur)
		var best: Vector2i = Vector2i(-1, -1)
		var best_d: int = -1
		var fallback: Vector2i = Vector2i(-1, -1)
		for nxt in _cached_moves_rotated(cur, sid, rot):
			if occ.has(nxt): continue
			if fallback == Vector2i(-1, -1): fallback = nxt
			var d: int = _bfs_dist(board, nxt, sid, occ, enemy_targets)
			if d > best_d:
				best_d = d; best = nxt
		var chosen: Vector2i = best if best != Vector2i(-1, -1) else fallback
		if chosen == Vector2i(-1, -1):
			occ[cur] = true; break
		plan.append({"type": "move", "from": cur, "to": chosen, "captured": false})
		occ[chosen] = true
		cur = chosen
	return plan

## Bey detects a capture reachable by FIRST rotating a drone (up to 5 chains,
## rotations included): rotate to line up a 1-hop take, capture, then poke.
func _bey_rotation_capture(board: Node2D, my_sid_map: Dictionary,
						   enemy_sid_map: Dictionary, movement_points: int) -> Array:
	if movement_points < 2 or enemy_sid_map.is_empty():
		return []
	for pos in my_sid_map:
		if not board.is_edge_tile(pos):
			continue
		var sid: int = my_sid_map[pos]
		for steps in [1, 2, 3, 4, 5]:
			for to in _cached_moves_rotated(pos, sid, steps):
				if not enemy_sid_map.has(to):
					continue
				var plan: Array = [{"type": "rotate", "at": pos, "degrees": float(steps) * 60.0}]
				plan.append({"type": "move", "from": pos, "to": to, "captured": true})
				var new_my: Dictionary = my_sid_map.duplicate()
				new_my.erase(pos); new_my[to] = sid
				var new_enemy: Dictionary = enemy_sid_map.duplicate()
				new_enemy.erase(to)
				plan.append_array(_bey_retreat(board, to, sid, steps, new_my, new_enemy, movement_points - 2))
				return plan
	return []

## Bey rotates a drone (on a rotation tile) toward the enemy majority (centroid):
## the drone + rotation whose move pattern best steps toward the bulk.
func _bey_rotate_toward_majority(board: Node2D, my_sid_map: Dictionary,
								 enemy_sid_map: Dictionary, movement_points: int) -> Array:
	if movement_points < 1 or enemy_sid_map.is_empty():
		return []
	var cx: int = 0
	var cy: int = 0
	for ep in enemy_sid_map:
		cx += ep.x; cy += ep.y
	var n: int = enemy_sid_map.size()
	var centroid: Vector2i = Vector2i(int(round(float(cx) / float(n))), int(round(float(cy) / float(n))))
	var best_plan: Array = []
	var best_gain: int = 0
	for pos in my_sid_map:
		if not board.is_edge_tile(pos):
			continue
		var sid: int = my_sid_map[pos]
		var cur_d: int = _cube_dist(pos, centroid)
		for steps in [1, 2, 3, 4, 5]:
			var gain: int = 0
			for to in _cached_moves_rotated(pos, sid, steps):
				gain = maxi(gain, cur_d - _cube_dist(to, centroid))
			if gain > best_gain:
				best_gain = gain
				best_plan = [{"type": "rotate", "at": pos, "degrees": float(steps) * 60.0}]
	## Fill the rest of the turn closing in on the enemy (bey is aggressive).
	if not best_plan.is_empty() and movement_points > 1:
		best_plan.append_array(_reposition_steps(board, my_sid_map, enemy_sid_map, movement_points - 1, 1))
	return best_plan

## Bey's reaching capture: the richest single-drone capture chain across all of
## bey's drones (material-maximising, same search the standard bots use). Returns
## {"plan": Array, "captures": int}; plan is [] when nothing is reachable.
func _bey_best_chain(board: Node2D, my_sid_map: Dictionary, enemy_sid_map: Dictionary, movement_points: int) -> Dictionary:
	var best_plan: Array = []
	var best_mat: float  = 0.0
	var best_caps: int   = 0
	for pos in my_sid_map:
		var chain: Array = _capture_chain_from(board, my_sid_map, enemy_sid_map, pos, movement_points, movement_points)
		if chain.is_empty():
			continue
		var mat: float = 0.0
		var caps: int  = 0
		for s in chain:
			if s.get("captured", false):
				mat += _piece_value(enemy_sid_map.get(s.get("to"), 8))
				caps += 1
		if mat > best_mat:
			best_mat = mat; best_plan = chain; best_caps = caps
	return {"plan": best_plan, "captures": best_caps}

func _plan_turn_bey(board: Node2D, my_sid_map: Dictionary, enemy_sid_map: Dictionary, movement_points: int) -> Array:
	var captures: Array = _find_direct_captures(board, my_sid_map, enemy_sid_map)

	## 2+ captures: dive
	if captures.size() >= 2:
		return _plan_multi_capture(captures, movement_points)

	## 1 capture: always poke — capture then retreat with remaining movement
	if captures.size() == 1:
		return _bey_poke(board, captures[0], my_sid_map, enemy_sid_map, movement_points)

	## No direct capture — detect one reachable by rotating first (5 chains, incl.
	## rotations), then poke.
	var rcap: Array = _bey_rotation_capture(board, my_sid_map, enemy_sid_map, movement_points)
	if not rcap.is_empty():
		return rcap

	## Still no capture — sometimes rotate a drone toward the enemy majority
	## instead of just advancing.
	if _rng.randf() < BEY_ROTATE_CHANCE:
		var rmaj: Array = _bey_rotate_toward_majority(board, my_sid_map, enemy_sid_map, movement_points)
		if not rmaj.is_empty():
			return rmaj

	## Otherwise advance via the richest reachable capture chain (material-
	## maximising — the same search the standard bots use, so bey never settles for
	## a lone take when a same-length chain grabs more). A 2+ capture chain is a
	## dive (take the whole chain); a single capture is poked; nothing reachable
	## falls back to repositioning toward edge tiles.
	var bc: Dictionary = _bey_best_chain(board, my_sid_map, enemy_sid_map, movement_points)
	var adv: Array = bc["plan"]
	if adv.is_empty():
		return _bey_reposition(board, my_sid_map, enemy_sid_map, movement_points)
	if int(bc["captures"]) >= 2:
		return adv   ## dive — take the whole multi-capture chain, no retreat
	## Single capture — poke: replay the pre-capture hops, then retreat.
	var cap_idx: int = -1
	for i in adv.size():
		if adv[i].get("captured", false):
			cap_idx = i
	var cap_step: Dictionary = adv[cap_idx]
	var poke_cap: Dictionary = {"from": cap_step["from"], "to": cap_step["to"]}
	var pre_my: Dictionary = my_sid_map.duplicate()
	for i in cap_idx:
		var step_sid: int = pre_my.get(adv[i]["from"], 0)
		pre_my.erase(adv[i]["from"])
		pre_my[adv[i]["to"]] = step_sid
	var poke_budget: int = movement_points - cap_idx
	var result: Array = []
	for i in cap_idx:
		result.append(adv[i])
	result.append_array(_bey_poke(board, poke_cap, pre_my, enemy_sid_map, poke_budget))
	return result
## HELPERS — Geometry
## ══════════════════════════════════════════════════════════════════════

## Geometric move-pattern lookup for (pos, sid, rot_steps), memoized for the
## current evaluate_position — see _geo_moves_cache.
func _cached_moves_rotated(pos: Vector2i, sid: int, rot_steps: int) -> Array:
	## Round 46 — native-hashed Vector3i key instead of a formatted string:
	## ~4x faster lookups in the BFS inner loop (measured). rot_steps is 0-5,
	## so sid*8+rot_steps is a collision-free encoding of (sid, rot_steps).
	## .get(null) collapses the has()+[] double-lookup; stored values are always
	## Arrays, so a null result unambiguously means "not cached yet".
	var key := Vector3i(pos.x, pos.y, sid * 8 + rot_steps)
	var cached = _geo_moves_cache.get(key)
	if cached == null:
		cached = game_manager.board.get_valid_move_coords_for_rotated(pos, sid, rot_steps)
		_geo_moves_cache[key] = cached
	return cached

## Round 30 — "think ahead during the roll". Called by GameManager as soon as
## the human's turn ends (current_player flips to the bot, before the
## roll-dice delay/animation even starts). movement_points isn't known yet --
## that's the dice roll -- so the actual chain search (_plan_turn) can't run,
## but the FIRST thing every chain search does for every piece is read its
## geometric move options at rot_steps 0-5 (_search_chain_for_piece's first
## hop enumeration, plus the edge-tile rotation candidates). That lookup
## depends only on the piece's current square + rotation, not on the roll --
## so do it now, for every piece on the board (ours AND the opponent's, since
## _build_target_values/_count_attackers/_search_escape_* all probe enemy
## moves too), while the dice are still settling.
##
## evaluate_position's _geo_cache_version check (see _geo_moves_cache) keeps
## this work intact for the evaluate_position call that follows, as long as
## nothing has moved in the meantime.
func prewarm_move_cache(board: Node2D, my_pieces: Array, enemy_pieces: Array) -> void:
	_geo_moves_cache.clear()
	for pos in my_pieces + enemy_pieces:
		var sid: int = int(board.get_piece_at(pos).get("source_id", -1))
		if sid < 0:
			continue
		for rot_steps in range(0, 6):
			_cached_moves_rotated(pos, sid, rot_steps)
	_geo_cache_version = game_manager.get_board_version()
