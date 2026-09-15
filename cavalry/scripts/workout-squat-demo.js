// Animated gym workout prototype: side-view bodyweight squat.
// Run from Window > Scripts > Silen > workout-squat-demo.

var BODY = "#4F7CFF";
var JOINT = "#DDE7FF";
var ACCENT = "#41D6A3";
var GROUND = "#273044";
var THICKNESS = 22;

var frames = [0, 12, 36, 48, 72];

// Each pose uses joint coordinates in composition space.
var standing = {
    head: [0, -250], neck: [0, -205], shoulder: [0, -175],
    hip: [0, 25], knee: [18, 145], ankle: [18, 265], toe: [112, 265],
    elbow: [52, -72], hand: [28, 25]
};

var squat = {
    head: [-105, -105], neck: [-86, -66], shoulder: [-72, -40],
    hip: [-18, 82], knee: [122, 132], ankle: [18, 265], toe: [112, 265],
    elbow: [5, -8], hand: [108, 8]
};

var poses = [standing, standing, squat, squat, standing];

function segmentValues(a, b) {
    var dx = b[0] - a[0];
    var dy = b[1] - a[1];
    return {
        x: (a[0] + b[0]) * 0.5,
        y: (a[1] + b[1]) * 0.5,
        length: Math.sqrt(dx * dx + dy * dy),
        rotation: Math.atan2(dy, dx) * 180 / Math.PI - 90
    };
}

function makeSegment(name, jointA, jointB, color, thickness) {
    var first = segmentValues(poses[0][jointA], poses[0][jointB]);
    var id = api.primitive("rectangle", name);

    api.set(id, {
        "generator.dimensions": [thickness, first.length],
        "position.x": first.x,
        "position.y": first.y,
        "rotation": first.rotation,
        "material.materialColor": color
    });

    for (var i = 0; i < frames.length; i++) {
        var value = segmentValues(poses[i][jointA], poses[i][jointB]);
        api.keyframe(id, frames[i], {
            "position.x": value.x,
            "position.y": value.y,
            "rotation": value.rotation,
            "generator.dimensions.y": value.length
        });
    }

    return id;
}

function makeJoint(name, jointName, radius, color) {
    var id = api.primitive("ellipse", name);

    api.set(id, {
        "generator.radius": [radius, radius],
        "material.materialColor": color
    });

    for (var i = 0; i < frames.length; i++) {
        api.keyframe(id, frames[i], {
            "position.x": poses[i][jointName][0],
            "position.y": poses[i][jointName][1]
        });
    }

    return id;
}

// Ground and foot provide a stable reference for the movement.
var groundId = api.primitive("rectangle", "Squat - Ground");
api.set(groundId, {
    "generator.dimensions": [700, 10],
    "position.x": 0,
    "position.y": 292,
    "material.materialColor": GROUND
});

makeSegment("Squat - Torso", "shoulder", "hip", BODY, 34);
makeSegment("Squat - Thigh", "hip", "knee", BODY, THICKNESS);
makeSegment("Squat - Shin", "knee", "ankle", BODY, THICKNESS);
makeSegment("Squat - Foot", "ankle", "toe", ACCENT, 18);
makeSegment("Squat - Upper Arm", "shoulder", "elbow", BODY, 16);
makeSegment("Squat - Forearm", "elbow", "hand", BODY, 16);
makeSegment("Squat - Neck", "neck", "shoulder", BODY, 18);

makeJoint("Squat - Head", "head", 38, JOINT);
makeJoint("Squat - Shoulder Joint", "shoulder", 18, JOINT);
makeJoint("Squat - Hip Joint", "hip", 19, ACCENT);
makeJoint("Squat - Knee Joint", "knee", 17, ACCENT);
makeJoint("Squat - Ankle Joint", "ankle", 14, JOINT);
makeJoint("Squat - Elbow Joint", "elbow", 12, JOINT);
makeJoint("Squat - Hand", "hand", 12, JOINT);

api.play();
console.info("Workout demo created: side-view squat, frames 0-72.");

