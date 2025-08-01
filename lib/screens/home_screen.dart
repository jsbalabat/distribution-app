import 'package:flutter/material.dart';
import 'dashboard_screen.dart';
import 'transaction_detail_screen.dart';
import 'submissions_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  static const List<Widget> _pages = <Widget>[
    DashboardScreen(),
    // SubmissionsScreen(),
    TransactionDetailScreen(),
    // Future: Add ItemsScreen(), ReportsScreen(), etc.
  ];

  void _onItemTapped(int index) {
    setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        selectedItemColor: Colors.teal,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          // BottomNavigationBarItem(
          //   icon: Icon(Icons.list_alt),
          //   label: 'Submissions',
          // ),
          // Future:
          BottomNavigationBarItem(
            icon: Icon(Icons.inventory),
            label: 'Items',
          ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.pushNamed(context, '/form'),
        label: const Text('New SOR'),
        icon: const Icon(Icons.add),
      ),
    );
  }
}