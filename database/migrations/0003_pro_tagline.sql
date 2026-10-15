-- The Pro tagline promised "predictive PR curves", which the app never shipped.
-- It now names what Pro actually includes.

UPDATE dbo.subscriptionplans
SET tagline = 'Per-exercise 1RM charts, AI monthly overviews, and automated deload signals.'
WHERE code = 'PRO'
  AND tagline = 'Advanced volume telemetry, predictive PR curves, and automated deload signals.';
