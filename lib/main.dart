import 'package:flutter/material.dart';
import 'gyarto_parositas.dart'; // ← a saját oldalad

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gyártó párosítás',
      debugShowCheckedModeBanner: false,
      home: MainLayout(), // ← itt jön a menü + tartalom
    );
  }
}

class MainLayout extends StatefulWidget {
  const MainLayout({super.key});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  int selectedIndex = 0;

  final List<Widget> pages = [
    GyartoParositasPage(),
    Center(child: Text('Beállítások oldal (hamarosan)')),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            extended: true,
            selectedIndex: selectedIndex,
            onDestinationSelected: (index) {
              setState(() {
                selectedIndex = index;
              });
            },
            selectedIconTheme: const IconThemeData(color: Colors.deepPurple, size: 24),
            selectedLabelTextStyle: const TextStyle(color: Colors.deepPurple),
            backgroundColor: const Color.fromARGB(255, 245, 245, 245),
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.link),
                label: Text('Gyártó párosítás'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.settings),
                label: Text('Beállítások'),
              ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: pages[selectedIndex],
          ),
        ],
      ),
    );
  }
}
