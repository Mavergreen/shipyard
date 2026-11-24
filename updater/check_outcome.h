#ifndef MAVERICKS_CHECK_OUTCOME_H
#define MAVERICKS_CHECK_OUTCOME_H

typedef enum {
    MAV_CHECK_FOUND = 0,
    MAV_CHECK_NOT_FOUND,
    MAV_CHECK_ABORTED,
    MAV_CHECK_TIMED_OUT
} mav_check_outcome_t;

static inline int
mav_check_records_completion(int pane_hint, mav_check_outcome_t outcome) {
    return pane_hint && (outcome == MAV_CHECK_FOUND || outcome == MAV_CHECK_NOT_FOUND);
}

static inline int
mav_check_exit_status(int pane_hint, mav_check_outcome_t outcome) {
    return (pane_hint && (outcome == MAV_CHECK_ABORTED || outcome == MAV_CHECK_TIMED_OUT)) ? 1 : 0;
}
#endif
