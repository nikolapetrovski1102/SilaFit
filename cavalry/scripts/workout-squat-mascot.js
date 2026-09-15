// SilenFit mascot workout rig: front-view bodyweight squat.
// Based on cavalry/assets/mascot-skeleton-reference.png.
// Run from Window > Scripts > Silen > workout-squat-mascot.

var LIME = "#DFFF19";
var LIME_LIGHT = "#EDFF67";
var BLACK = "#10130A";
var ORANGE = "#FFB45C";
var SHADOW = "#253327";
var OUTLINE = 5;

// Make the generator repeat-safe: replace only layers created by this rig.
var existingLayers = api.getCompLayers(false);
for (var existingIndex = existingLayers.length - 1; existingIndex >= 0; existingIndex--) {
    var existingName = api.getNiceName(existingLayers[existingIndex]);
    if (existingName.indexOf("Mascot Rig - ") === 0 ||
        existingName.indexOf("Squat - ") === 0) {
        api.deleteLayer(existingLayers[existingIndex]);
    }
}

// Compact 2.4-second loop at the default 25 fps, matching the reference's
// quick, readable exercise-icon cadence.
var frames = [0, 6, 17, 26, 32, 43, 52, 60];
var depths = [0, 0.18, 0.62, 1, 1, 0.62, 0.18, 0];

var upright = {
    head: [0, -300], neck: [0, -238],
    shoulderL: [-98, -198], shoulderR: [98, -198],
    hipL: [-48, 30], hipR: [48, 30],
    kneeL: [-58, 165], kneeR: [58, 165],
    ankleL: [-66, 298], ankleR: [66, 298],
    toeL: [-128, 298], toeR: [128, 298],
    elbowL: [-144, -55], elbowR: [144, -55],
    wristL: [-125, 62], wristR: [125, 62]
};

var bottom = {
    head: [0, -174], neck: [0, -114],
    shoulderL: [-105, -78], shoulderR: [105, -78],
    hipL: [-62, 104], hipR: [62, 104],
    kneeL: [-150, 202], kneeR: [150, 202],
    ankleL: [-112, 298], ankleR: [112, 298],
    toeL: [-174, 298], toeR: [174, 298],
    elbowL: [-157, 34], elbowR: [157, 34],
    wristL: [-125, 126], wristR: [125, 126]
};

function mix(a, b, amount) {
    return [
        a[0] + (b[0] - a[0]) * amount,
        a[1] + (b[1] - a[1]) * amount
    ];
}

function twoBoneJoint(start, end, firstLength, secondLength, bendSide) {
    var dx = end[0] - start[0];
    var dy = end[1] - start[1];
    var distance = Math.sqrt(dx * dx + dy * dy);
    var minimum = Math.abs(firstLength - secondLength) + 0.001;
    var maximum = firstLength + secondLength - 0.001;
    distance = Math.max(minimum, Math.min(maximum, distance));

    var along = (firstLength * firstLength - secondLength * secondLength + distance * distance) /
        (2 * distance);
    var height = Math.sqrt(Math.max(0, firstLength * firstLength - along * along));
    var unitX = dx / distance;
    var unitY = dy / distance;
    var baseX = start[0] + unitX * along;
    var baseY = start[1] + unitY * along;

    return [
        baseX + (-unitY) * height * bendSide,
        baseY + unitX * height * bendSide
    ];
}

function buildPose(amount) {
    var imagePose = {};
    var names = Object.keys(upright);
    for (var i = 0; i < names.length; i++) {
        var name = names[i];
        imagePose[name] = mix(upright[name], bottom[name], amount);
    }

    // Solve elbows and knees from fixed bone lengths. This prevents the
    // rubbery stretching that simple point interpolation creates.
    imagePose.kneeL = twoBoneJoint(imagePose.hipL, imagePose.ankleL, 136, 133, 1);
    imagePose.kneeR = twoBoneJoint(imagePose.hipR, imagePose.ankleR, 136, 133, -1);
    imagePose.elbowL = twoBoneJoint(imagePose.shoulderL, imagePose.wristL, 151, 121, 1);
    imagePose.elbowR = twoBoneJoint(imagePose.shoulderR, imagePose.wristR, 151, 121, -1);

    var pose = {};
    for (var pointIndex = 0; pointIndex < names.length; pointIndex++) {
        var pointName = names[pointIndex];
        var imagePoint = imagePose[pointName];
        // Reference-image Y increases downward; Cavalry Y increases upward.
        pose[pointName] = [imagePoint[0], -imagePoint[1]];
    }
    return pose;
}

var poses = [];
for (var poseIndex = 0; poseIndex < depths.length; poseIndex++) {
    poses.push(buildPose(depths[poseIndex]));
}

function polygon(points, name, fillColor) {
    var path = new cavalry.Path();
    path.moveTo(points[0][0], -points[0][1]);
    for (var i = 1; i < points.length; i++) {
        path.lineTo(points[i][0], -points[i][1]);
    }
    path.close();

    var id = api.createEditable(path, name);
    api.setFill(id, true);
    api.setStroke(id, true);
    api.set(id, {
        "material.materialColor": fillColor,
        "stroke.strokeColor": BLACK,
        "stroke.width": OUTLINE
    });
    return id;
}

function ellipse(name, radiusX, radiusY, fillColor, withStroke) {
    var id = api.primitive("ellipse", name);
    api.set(id, {
        "generator.radius": [radiusX, radiusY],
        "material.materialColor": fillColor
    });
    api.setStroke(id, withStroke);
    if (withStroke) {
        api.set(id, {"stroke.strokeColor": BLACK, "stroke.width": OUTLINE});
    }
    return id;
}

function segmentData(a, b) {
    var dx = b[0] - a[0];
    var dy = b[1] - a[1];
    return {
        x: (a[0] + b[0]) * 0.5,
        y: (a[1] + b[1]) * 0.5,
        length: Math.sqrt(dx * dx + dy * dy),
        rotation: Math.atan2(dy, dx) * 180 / Math.PI - 90
    };
}

function animatePosition(id, pointName) {
    for (var i = 0; i < frames.length; i++) {
        api.keyframe(id, frames[i], {
            "position.x": poses[i][pointName][0],
            "position.y": poses[i][pointName][1]
        });
    }
}

function makeLimb(name, pointA, pointB, topWidth, bottomWidth, color) {
    var initial = segmentData(poses[0][pointA], poses[0][pointB]);
    var half = initial.length * 0.5;
    var id = polygon([
        [-topWidth * 0.5, -half],
        [topWidth * 0.5, -half],
        [bottomWidth * 0.5, half],
        [-bottomWidth * 0.5, half]
    ], name, color);

    for (var i = 0; i < frames.length; i++) {
        var value = segmentData(poses[i][pointA], poses[i][pointB]);
        api.keyframe(id, frames[i], {
            "position.x": value.x,
            "position.y": value.y,
            "rotation": value.rotation
        });
    }
    return id;
}

function pointAlong(a, b, amount) {
    return [
        a[0] + (b[0] - a[0]) * amount,
        a[1] + (b[1] - a[1]) * amount
    ];
}

function makeWristband(name, elbowName, wristName) {
    var firstA = pointAlong(poses[0][elbowName], poses[0][wristName], 0.82);
    var firstB = pointAlong(poses[0][elbowName], poses[0][wristName], 0.98);
    var initial = segmentData(firstA, firstB);
    var id = polygon([
        [-18, -initial.length * 0.5], [18, -initial.length * 0.5],
        [18, initial.length * 0.5], [-18, initial.length * 0.5]
    ], name, ORANGE);

    for (var i = 0; i < frames.length; i++) {
        var a = pointAlong(poses[i][elbowName], poses[i][wristName], 0.82);
        var b = pointAlong(poses[i][elbowName], poses[i][wristName], 0.98);
        var value = segmentData(a, b);
        api.keyframe(id, frames[i], {
            "position.x": value.x,
            "position.y": value.y,
            "rotation": value.rotation,
            "scale.y": value.length / initial.length
        });
    }
    return id;
}

function makeHand(name, elbowName, wristName) {
    var id = polygon([
        [-18, -20], [12, -24], [23, -8], [18, 17],
        [0, 29], [-20, 15], [-25, -5]
    ], name, LIME);

    for (var i = 0; i < frames.length; i++) {
        var elbow = poses[i][elbowName];
        var wrist = poses[i][wristName];
        var dx = wrist[0] - elbow[0];
        var dy = wrist[1] - elbow[1];
        var length = Math.sqrt(dx * dx + dy * dy);
        var x = wrist[0] + dx / length * 22;
        var y = wrist[1] + dy / length * 22;
        var rotation = Math.atan2(dy, dx) * 180 / Math.PI - 90;
        api.keyframe(id, frames[i], {
            "position.x": x,
            "position.y": y,
            "rotation": rotation
        });
    }
    return id;
}

function makeFoot(name, ankleName, toeName, isLeft) {
    var points = isLeft ?
        [[-52, -17], [13, -17], [22, 18], [-44, 18]] :
        [[-13, -17], [52, -17], [44, 18], [-22, 18]];
    var id = polygon(points, name, LIME);
    var initialWidth = Math.abs(poses[0][toeName][0] - poses[0][ankleName][0]);

    for (var i = 0; i < frames.length; i++) {
        var ankle = poses[i][ankleName];
        var toe = poses[i][toeName];
        var width = Math.abs(toe[0] - ankle[0]);
        api.keyframe(id, frames[i], {
            "position.x": (ankle[0] + toe[0]) * 0.5,
            "position.y": ankle[1],
            "scale.x": width / initialWidth
        });
    }
    return id;
}

function makeJointCap(name, pointName, radius, color) {
    var id = ellipse(name, radius, radius, color, true);
    animatePosition(id, pointName);
    return id;
}

// Background reference elements.
var shadowId = ellipse("Mascot Rig - Ground Shadow", 175, 24, SHADOW, false);
api.set(shadowId, {"position.x": 0, "position.y": -316, "opacity": 0.45});

// Legs are created first so the torso and pelvis overlap their top edges.
makeLimb("Mascot Rig - Left Thigh", "hipL", "kneeL", 52, 42, LIME);
makeLimb("Mascot Rig - Right Thigh", "hipR", "kneeR", 52, 42, LIME);
makeLimb("Mascot Rig - Left Shin", "kneeL", "ankleL", 42, 34, LIME_LIGHT);
makeLimb("Mascot Rig - Right Shin", "kneeR", "ankleR", 42, 34, LIME_LIGHT);
makeFoot("Mascot Rig - Left Foot", "ankleL", "toeL", true);
makeFoot("Mascot Rig - Right Foot", "ankleR", "toeR", false);

// Arms follow the separated-layer structure in the supplied mascot sheet.
makeLimb("Mascot Rig - Left Upper Arm", "shoulderL", "elbowL", 48, 38, LIME);
makeLimb("Mascot Rig - Right Upper Arm", "shoulderR", "elbowR", 48, 38, LIME);
makeLimb("Mascot Rig - Left Forearm", "elbowL", "wristL", 37, 30, LIME_LIGHT);
makeLimb("Mascot Rig - Right Forearm", "elbowR", "wristR", 37, 30, LIME_LIGHT);
makeWristband("Mascot Rig - Left Wristband", "elbowL", "wristL");
makeWristband("Mascot Rig - Right Wristband", "elbowR", "wristR");
makeHand("Mascot Rig - Left Hand", "elbowL", "wristL");
makeHand("Mascot Rig - Right Hand", "elbowR", "wristR");

// Rounded joint caps match the compact articulated style in the motion reference.
makeJointCap("Mascot Rig - Left Elbow", "elbowL", 18, LIME_LIGHT);
makeJointCap("Mascot Rig - Right Elbow", "elbowR", 18, LIME_LIGHT);
makeJointCap("Mascot Rig - Left Knee", "kneeL", 20, LIME);
makeJointCap("Mascot Rig - Right Knee", "kneeR", 20, LIME);
makeJointCap("Mascot Rig - Left Ankle", "ankleL", 16, LIME_LIGHT);
makeJointCap("Mascot Rig - Right Ankle", "ankleR", 16, LIME_LIGHT);

// Pelvis and torso retain the mascot's broad-shouldered silhouette.
var pelvisId = polygon([
    [-70, -38], [70, -38], [82, 23], [38, 40],
    [18, 18], [-18, 18], [-38, 40], [-82, 23]
], "Mascot Rig - Pelvis", LIME);

var torsoId = polygon([
    [-98, -112], [98, -112], [122, -70], [78, 110],
    [34, 120], [-34, 120], [-78, 110], [-122, -70]
], "Mascot Rig - Torso", LIME);

for (var i = 0; i < frames.length; i++) {
    var shoulderCentre = mix(poses[i].shoulderL, poses[i].shoulderR, 0.5);
    var hipCentre = mix(poses[i].hipL, poses[i].hipR, 0.5);
    var torsoCentre = mix(shoulderCentre, hipCentre, 0.5);
    var torsoHeight = Math.abs(hipCentre[1] - shoulderCentre[1]);

    api.keyframe(torsoId, frames[i], {
        "position.x": torsoCentre[0],
        "position.y": torsoCentre[1],
        "scale.x": 1 - depths[i] * 0.06,
        "scale.y": torsoHeight / 228
    });

    api.keyframe(pelvisId, frames[i], {
        "position.x": hipCentre[0],
        "position.y": hipCentre[1] + 18,
        "scale.x": 1 + depths[i] * 0.13,
        "scale.y": 1 - depths[i] * 0.08
    });
}

var neckId = polygon([
    [-19, -19], [19, -19], [23, 17], [12, 25], [-12, 25], [-23, 17]
], "Mascot Rig - Neck", LIME_LIGHT);
animatePosition(neckId, "neck");

var headId = ellipse("Mascot Rig - Head", 60, 60, LIME_LIGHT, true);
animatePosition(headId, "head");

var eyeLeftId = ellipse("Mascot Rig - Left Eye", 8, 10, BLACK, false);
var eyeRightId = ellipse("Mascot Rig - Right Eye", 8, 10, BLACK, false);
for (var eyeFrame = 0; eyeFrame < frames.length; eyeFrame++) {
    var head = poses[eyeFrame].head;
    api.keyframe(eyeLeftId, frames[eyeFrame], {
        "position.x": head[0] - 21, "position.y": head[1] - 2
    });
    api.keyframe(eyeRightId, frames[eyeFrame], {
        "position.x": head[0] + 21, "position.y": head[1] - 2
    });
}

api.play();
console.info("SilenFit mascot squat created: rigid layered rig, 8 poses, frames 0-60.");
