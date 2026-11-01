import '../../core/widgets/mascot/flame_mascot.dart';
import '../../core/widgets/mascot/talking_mascot.dart';
import 'onboarding_controller.dart';

/// What Sila says on each onboarding step. Lines are kept short enough to
/// fit the speech bubble in two lines on a small phone.
MascotLine? mascotLineFor(OnboardingStep step) => switch (step) {
      OnboardingStep.intro => null,
      OnboardingStep.gender => const MascotLine(
          FlameArt.laughing, "Hey, I'm Sila! Let's build a plan that fits you."),
      OnboardingStep.age => const MascotLine(
          FlameArt.smug, 'Age is just a number, but it helps me tune your plan.'),
      OnboardingStep.height => const MascotLine(
          FlameArt.determined, 'Stand tall! This helps me size your workouts.'),
      OnboardingStep.weight => const MascotLine(
          FlameArt.smug, "No judgment here. It's just your starting point."),
      OnboardingStep.goal => const MascotLine(
          FlameArt.determined, "What are we chasing? I'll keep the fire going."),
      OnboardingStep.trainingDays => const MascotLine(
          FlameArt.laughing, 'How many days a week can I count on you?'),
      OnboardingStep.trainingExperience => const MascotLine(
          FlameArt.smug, "Be honest. I'll match your pace."),
      OnboardingStep.equipmentAccess => const MascotLine(
          FlameArt.determined, 'Gym, home or bodyweight. I burn anywhere.'),
      OnboardingStep.dailyActivity => const MascotLine(
          FlameArt.laughing, 'Last one! How active is a normal day for you?'),
      OnboardingStep.notifications => const MascotLine(
          FlameArt.shocked, "Don't let me burn out! I'll nudge you on workout days."),
    };
