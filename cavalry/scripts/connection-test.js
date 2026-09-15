// Silen / Codex -> Cavalry connection test
// Run from Window > Scripts > Silen > connection-test.

var circleId = api.primitive("ellipse", "Codex Connection Test");

api.set(circleId, {
    "generator.radius": [80, 80],
    "position.x": -300,
    "position.y": 0,
    "material.materialColor": "#4F7CFF"
});

api.keyframe(circleId, 0, {
    "position.x": -300
});

api.keyframe(circleId, 60, {
    "position.x": 300
});

console.info("Codex connection successful: animated test circle created.");

