import '../app_localizations.dart';
import '../app_state.dart';

class Player {
  const Player({
    required this.name,
    required this.greeting,
    required this.level,
    required this.rank,
    required this.xp,
    required this.xpToNext,
    required this.coins,
    required this.streak,
  });

  final String name;
  final String greeting;
  final int level;
  final String rank;
  final int xp;
  final int xpToNext;
  final int coins;
  final int streak;
}

class DailyChallenge {
  const DailyChallenge({
    required this.id,
    required this.index,
    required this.title,
    required this.goal,
    required this.done,
    required this.coins,
    required this.xp,
    required this.status,
  });

  final String id;
  final int index;
  final String title;
  final int goal;
  final int done;
  final int coins;
  final int xp;
  final String status;
}

class Drill {
  const Drill({
    required this.id,
    required this.name,
    required this.category,
    required this.difficulty,
    required this.image,
    required this.duration,
  });

  final String id;
  final String name;
  final String category;
  final String difficulty;
  final String image;
  final String duration;
}

class Program {
  const Program({
    required this.id,
    required this.name,
    required this.drills,
    required this.difficulty,
    required this.image,
  });

  final String id;
  final String name;
  final int drills;
  final String difficulty;
  final String image;
}

Player get player => Player(
  name: currentUserName,
  greeting: 'Good afternoon,',
  level: 1,
  rank: 'Beginner',
  xp: 0,
  xpToNext: 300,
  coins: 120,
  streak: 0,
);

const dailyChallenges = [
  DailyChallenge(
    id: 'c1',
    index: 1,
    title: 'Complete Hand Reaction 3 times',
    goal: 3,
    done: 0,
    coins: 25,
    xp: 50,
    status: 'todo',
  ),
  DailyChallenge(
    id: 'c2',
    index: 2,
    title: 'Score 80+ on Foot Reaction',
    goal: 1,
    done: 0,
    coins: 30,
    xp: 60,
    status: 'todo',
  ),
  DailyChallenge(
    id: 'c3',
    index: 3,
    title: 'Hold a perfect plank for 60s',
    goal: 1,
    done: 0,
    coins: 20,
    xp: 40,
    status: 'todo',
  ),
];

const drills = [
  Drill(
    id: 'hand-reaction',
    name: 'Hand Reaction',
    category: 'Reaction',
    difficulty: 'Beginner',
    image: 'assets/images/onboard-1-ai.jpg',
    duration: '3 min',
  ),
  Drill(
    id: 'foot-reaction',
    name: 'Foot Reaction',
    category: 'Reaction',
    difficulty: 'Beginner',
    image: 'assets/images/drill-foot-reaction.jpg',
    duration: '4 min',
  ),
  Drill(
    id: 'get-in-box',
    name: 'Get In The Box',
    category: 'Fitness',
    difficulty: 'Beginner',
    image: 'assets/images/onboard-3-levelup.jpg',
    duration: '5 min',
  ),
  Drill(
    id: 'rain-body',
    name: 'The Rain (Body)',
    category: 'Reaction',
    difficulty: 'Intermediate',
    image: 'assets/images/drill-rain-body.jpg',
    duration: '6 min',
  ),
  Drill(
    id: 'rain-feet',
    name: 'The Rain (Feet)',
    category: 'Reaction',
    difficulty: 'Advanced',
    image: 'assets/images/drill-rain-body.jpg',
    duration: '7 min',
  ),
  Drill(
    id: 'ball-control',
    name: 'Close Control',
    category: 'Control',
    difficulty: 'Intermediate',
    image: 'assets/images/onboard-2-drills.jpg',
    duration: '5 min',
  ),
  Drill(
    id: 'first-touch',
    name: 'First Touch',
    category: 'Control',
    difficulty: 'Beginner',
    image: 'assets/images/onboard-2-drills.jpg',
    duration: '4 min',
  ),
  Drill(
    id: 'sprint-cube',
    name: 'Sprint Cube',
    category: 'Fitness',
    difficulty: 'Advanced',
    image: 'assets/images/onboard-3-levelup.jpg',
    duration: '6 min',
  ),
  Drill(
    id: 'agility-grid',
    name: 'Agility Grid',
    category: 'Fitness',
    difficulty: 'Intermediate',
    image: 'assets/images/onboard-3-levelup.jpg',
    duration: '5 min',
  ),
  Drill(
    id: 'power-shot',
    name: 'Power Shot',
    category: 'Shooting',
    difficulty: 'Intermediate',
    image: 'assets/images/onboard-2-drills.jpg',
    duration: '5 min',
  ),
  Drill(
    id: 'finisher',
    name: 'Finisher',
    category: 'Shooting',
    difficulty: 'Advanced',
    image: 'assets/images/onboard-2-drills.jpg',
    duration: '6 min',
  ),
];

const programs = [
  Program(
    id: 'reaction-starter',
    name: 'Reaction Starter',
    drills: 5,
    difficulty: 'Beginner',
    image: 'assets/images/onboard-1-ai.jpg',
  ),
  Program(
    id: 'body-control',
    name: 'Body Control',
    drills: 5,
    difficulty: 'Beginner',
    image: 'assets/images/onboard-3-levelup.jpg',
  ),
  Program(
    id: 'elite-finisher',
    name: 'Elite Finisher',
    drills: 6,
    difficulty: 'Advanced',
    image: 'assets/images/drill-rain-body.jpg',
  ),
];

Drill drillById(String? id) {
  return drills.firstWhere((d) => d.id == id, orElse: () => drills.first);
}

String localizedCategory(String category) {
  return switch (category) {
    'All' => AppLocalizations.get('category_all'),
    'Reaction' => AppLocalizations.get('category_reaction'),
    'Control' => AppLocalizations.get('category_control'),
    'Fitness' => AppLocalizations.get('category_fitness'),
    'Shooting' => AppLocalizations.get('category_shooting'),
    _ => category,
  };
}

String localizedDifficulty(String difficulty) {
  return switch (difficulty) {
    'Beginner' => AppLocalizations.get('difficulty_beginner'),
    'Intermediate' => AppLocalizations.get('difficulty_intermediate'),
    'Advanced' => AppLocalizations.get('difficulty_advanced'),
    _ => difficulty,
  };
}

String localizedDrillName(String id, String fallback) {
  return AppLocalizations.get('drill_${id.replaceAll('-', '_')}') == 'drill_${id.replaceAll('-', '_')}'
      ? fallback
      : AppLocalizations.get('drill_${id.replaceAll('-', '_')}');
}

String localizedProgramName(String id, String fallback) {
  return AppLocalizations.get('program_${id.replaceAll('-', '_')}') == 'program_${id.replaceAll('-', '_')}'
      ? fallback
      : AppLocalizations.get('program_${id.replaceAll('-', '_')}');
}

String localizedChallengeTitle(String id, String fallback) {
  final key = 'challenge_$id';
  final value = AppLocalizations.get(key);
  return value == key ? fallback : value;
}
