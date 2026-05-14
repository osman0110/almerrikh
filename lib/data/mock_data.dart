import '../app_localizations.dart';

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

Drill drillById(String? id) {
  return drills.firstWhere((d) => d.id == id, orElse: () => drills.first);
}

String localizedDrillName(String id, String fallback) {
  return AppLocalizations.get('drill_${id.replaceAll('-', '_')}') == 'drill_${id.replaceAll('-', '_')}'
      ? fallback
      : AppLocalizations.get('drill_${id.replaceAll('-', '_')}');
}
