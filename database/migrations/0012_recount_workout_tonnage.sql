-- Recounts every completed workout's TonnageKg from its own set logs, so the
-- Progress screen's volume totals and the analytics agree with how the app
-- counts a workout from now on.
--
-- The active-workout tracker computes a session's tonnage when it finishes and
-- stores it here: weight x reps per completed set, with a Dumbbell set counted
-- twice because its logged weight is per hand. That doubling used to apply to
-- every Dumbbell exercise, including the ones done with a single dumbbell
-- (goblet squat, pullover, one-arm row, ...), and 0011 gave hundreds of catalog
-- exercises an equipment type for the first time - so older sessions were
-- counted under different rules than new ones. This applies the tracker's
-- current rule (`_loadMultiplierFor` in active_workout_tracker_screen.dart -
-- keep the two in step) to the sets each session actually logged.
--
-- Only sessions with set logs are touched; ones from before set logging, or
-- without any logged sets, keep the tonnage they were saved with.

UPDATE dbo.workoutsessions ws
SET tonnagekg = t.tonnagekg
FROM (
    SELECT l.workoutsessionid,
           NULLIF(SUM(l.weightkg * l.reps *
               CASE WHEN e.equipmenttype = 'Dumbbell'
                     AND NOT (e.name COLLATE "C" ~* (
                         'goblet|single[ -]arm|one[ -]arm|1-arm|tripod|pull ?over|concentration'
                         '|plie|sumo squat|side bend|knee-in|pass-through'
                         '|two arm dumbbell overhead|two arm seated dumbbell'
                         '|overhead dumbbell (extension|tricep)|dumbbell overhead (extension|tricep)'
                         '|dumbbell tricep overhead|seated dumbbell tricep extension'
                         '|triceps press with db|overhead triceps|behind head|french press'
                         '|weighted (ab )?crunch|1 db|dumbbell on chest'))
                    THEN 2 ELSE 1 END), 0)::numeric(10,2) AS tonnagekg
    FROM dbo.workoutsetlogs l
    JOIN dbo.exercises e ON e.exerciseid = l.exerciseid
    GROUP BY l.workoutsessionid
) t
WHERE ws.workoutsessionid = t.workoutsessionid
  AND ws.status = 'Completed'
  AND ws.tonnagekg IS DISTINCT FROM t.tonnagekg;
