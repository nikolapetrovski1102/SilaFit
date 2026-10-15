-- The Free tagline led with "hardware tracking", which the app doesn't do.
-- It now names what Free actually includes.

UPDATE dbo.subscriptionplans
SET tagline = 'Workout logging, ready-made splits and streak tracking for self-guided lifters.'
WHERE code = 'FREE'
  AND tagline = 'Essential hardware tracking and routine logging for self-guided lifters.';
