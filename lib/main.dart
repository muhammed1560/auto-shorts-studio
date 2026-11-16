// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'shorts_tab.dart';
import 'long_editor_tab.dart';
import 'projects_tab.dart';
import 'project_manager.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const DarwinInitializationSettings initializationSettingsDarwin = DarwinInitializationSettings(
    requestAlertPermission: true,
    requestBadgePermission: true,
    requestSoundPermission: true,
  );

  const InitializationSettings initializationSettings = InitializationSettings(
    macOS: initializationSettingsDarwin,
  );

  flutterLocalNotificationsPlugin.initialize(
    settings: initializationSettings,
  );

  await ProjectManager().init();

  runApp(const AutoShortsApp());
}

class AutoShortsApp extends StatelessWidget {
  const AutoShortsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AutoShorts Studio - AI Video Automation',
      theme: ThemeData.dark().copyWith(
        colorScheme: const ColorScheme.dark(
          primary: Colors.deepPurpleAccent,
          secondary: Colors.purpleAccent,
          surface: Color(0xFF1E1E2C),
        ),
        scaffoldBackgroundColor: const Color(0xFF12121D),
      ),
      home: const MainLayout(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class MainLayout extends StatefulWidget {
  const MainLayout({super.key});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  int _selectedIndex = 0;

  void _onEditProject(Project project) {
    setState(() {
      _selectedIndex = project.type == ProjectType.shorts ? 0 : 1;
      _pages = [
        ShortsTab(key: Key('shorts_${project.id}'), initialProject: project.type == ProjectType.shorts ? project : null),
        LongEditorTab(key: Key('long_${project.id}'), initialProject: project.type == ProjectType.longVideo ? project : null),
        ProjectsTab(onEditProject: _onEditProject),
      ];
    });
  }

  late List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _pages = [
      const ShortsTab(key: Key('shorts_initial')),
      const LongEditorTab(key: Key('long_initial')),
      ProjectsTab(onEditProject: _onEditProject),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AutoShorts Studio — AI Video Automation'),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          NavigationRail(
            selectedIndex: _selectedIndex,
            onDestinationSelected: (int index) {
              setState(() {
                _selectedIndex = index;
                if (index == 2) {
                  _pages[2] = ProjectsTab(key: UniqueKey(), onEditProject: _onEditProject);
                }
              });
            },
            backgroundColor: Theme.of(context).colorScheme.surface,
            labelType: NavigationRailLabelType.all,
            indicatorColor: Theme.of(context).colorScheme.primary.withOpacity(0.3),
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.flash_on_outlined),
                selectedIcon: Icon(Icons.flash_on),
                label: Text('Shorts Generator'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.movie_outlined),
                selectedIcon: Icon(Icons.movie),
                label: Text('Smart Long Editor'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.folder_outlined),
                selectedIcon: Icon(Icons.folder),
                label: Text('Workspace'),
              ),
            ],
          ),
          const VerticalDivider(thickness: 1, width: 1, color: Colors.white10),
          Expanded(
            child: IndexedStack(
              index: _selectedIndex,
              children: _pages,
            ),
          ),
        ],
      ),
    );
  }
}
