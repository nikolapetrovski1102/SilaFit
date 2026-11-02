import '../../core/widgets/mascot/ram_mascot.dart';
import '../../core/widgets/mascot/talking_mascot.dart';
import 'onboarding_controller.dart';

/// What Sila says on each onboarding step. Lines are kept short enough to
/// fit the speech bubble in two lines on a small phone.
MascotLine? mascotLineFor(OnboardingStep step) => switch (step) {
      OnboardingStep.intro => null,
      OnboardingStep.gender => const MascotLine(
          RamArt.laughing, "Hey, I'm Sila! Let's build a plan that fits you."),
      OnboardingStep.age => const MascotLine(
          RamArt.smug, 'Age is just a number, but it helps me tune your plan.'),
      OnboardingStep.height => const MascotLine(
          RamArt.determined, 'Stand tall! This helps me size your workouts.'),
      OnboardingStep.weight => const MascotLine(
          RamArt.smug, "No judgment here. It's just your starting point."),
      OnboardingStep.goal => const MascotLine(
          RamArt.determined, "What are we chasing? I'll keep us charging."),
      OnboardingStep.trainingDays => const MascotLine(
          RamArt.laughing, 'How many days a week can I count on you?'),
      OnboardingStep.trainingExperience => const MascotLine(
          RamArt.smug, "Be honest. I'll match your pace."),
      OnboardingStep.equipmentAccess => const MascotLine(
          RamArt.determined, 'Gym, home or bodyweight. I train anywhere.'),
      OnboardingStep.dailyActivity => const MascotLine(
          RamArt.laughing, 'Last one! How active is a normal day for you?'),
      OnboardingStep.notifications => const MascotLine(
          RamArt.shocked, "Don't let me get sleepy! I'll nudge you on workout days."),
    };
