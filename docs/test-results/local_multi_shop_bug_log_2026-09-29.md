# Local Multi-Shop Certification Bug Log

Date: 2026-09-29

| ID | Severity | Defect | Resolution | Status |
| --- | --- | --- | --- | --- |
| LMS-001 | High | A register reassigned to another shop retained stale inventory in the mounted shell | Keyed the hosted shell by business and shop, cleared shop-local inventory, and remounted after reassignment | Fixed and tested |
| LMS-002 | High | First-run Android database creation could exceed the short startup timeout | Increased the mobile database-open allowance and added a regression test | Fixed and tested |
| LMS-003 | High | Compact phone Sales could hide item/cart controls when the keyboard reduced height | Made the compact sales body scroll as one responsive pane and added widget coverage | Fixed and tested |
| LMS-004 | Medium | Shop creation dialog disposed text controllers before route completion | Replaced controller-dependent return handling with trimmed value state and added a widget test | Fixed and tested |
| LMS-005 | Medium | Enrollment shop selection could overflow or use an invalid dialog context | Bounded the selector and routed dialogs through the application navigator | Fixed and tested |
| LMS-006 | Medium | Reassignment confirmation used hardcoded pending/parked counts | Read live pending events, parked work, and cart state before allowing reassignment | Fixed and tested |
| LMS-007 | Medium | Barcode automation used Enter during a transition and could close the app | Switched the acceptance driver to the explicit Add Exact Match action | Fixed and tested |
| LMS-008 | Medium | A customer selection could not be reliably cleared on compact layouts | Added an always-available Clear Selected Customer suffix action | Fixed and tested |
| LMS-009 | Medium | Server E2E result JSON captured stale pre-acknowledgement counts | Refreshed final states after ACK waits and reject inconsistent result artifacts | Fixed and tested |
| LMS-010 | Medium | The server operational-row audit was optional | Added a mandatory configurable SSH/raw-SQL audit to the server E2E trigger | Fixed and tested |
| LMS-011 | Medium | Offline warnings exposed raw socket exceptions and backend URIs | Replaced transport detail with concise queued-data and reconnect guidance | Fixed and tested |

No unresolved blocker, critical, high, or medium defects remain in the certified scope.
