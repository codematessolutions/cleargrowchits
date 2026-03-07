import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'companyfinance.dart';
import 'staff_management_screen.dart';
import 'expense_screen.dart';
import 'kuri_list_screen.dart';
import 'login_page.dart';

class AdminHome extends StatefulWidget {
  final String userId;
  final String userName;
  final String userRole;

  const AdminHome({
    super.key,
    required this.userId,
    required this.userName,
    required this.userRole,
  });

  @override
  State<AdminHome> createState() => _AdminHomeState();
}

class _AdminHomeState extends State<AdminHome> {
  int _selectedIndex = 0;

  // --- LOGOUT ALERT DIALOG ---
  Future<void> _showLogoutDialog() async {
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.logout, color: Colors.redAccent),
            SizedBox(width: 10),
            Text("Confirm Logout", style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Text("Are you sure you want to sign out? Your session will be cleared."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              elevation: 0,
            ),
            onPressed: () async {
              final SharedPreferences prefs = await SharedPreferences.getInstance();
              await prefs.clear();
              if (mounted) {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginPage()),
                      (route) => false,
                );
              }
            },
            child: const Text("Logout", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Breakpoint: Web view > 800px, Mobile view <= 800px
    bool isWeb = MediaQuery.of(context).size.width > 800;

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      // Drawer is only used on mobile
      drawer: !isWeb ? Drawer(child: Container(color: const Color(0xFF1E3A8A), child: _buildSidebarContent())) : null,
      body: Row(
        children: [
          // Fixed Sidebar for Web
          if (isWeb)
            Container(
              width: 260,
              color: const Color(0xFF1E3A8A),
              child: _buildSidebarContent(),
            ),

          // Main Content Section
          Expanded(
            child: Column(
              children: [
                _buildWebTopBar(isWeb),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(30),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1000), // Limits content width for "Medium Container" feel
                        child: _buildDashboardContent(),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- TOP NAVIGATION BAR ---
  Widget _buildWebTopBar(bool isWeb) {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 1, offset: Offset(0, 1))],
      ),
      child: Row(
        children: [
          if (!isWeb)
            Builder(builder: (context) => IconButton(
              icon: const Icon(Icons.menu, color: Color(0xFF1E3A8A)),
              onPressed: () => Scaffold.of(context).openDrawer(),
            )),
          const Text("DASHBOARD", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2, fontSize: 16)),
          const Spacer(),
          Text("Welcome, ${widget.userName}", style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF334155))),
          const SizedBox(width: 15),
          const CircleAvatar(
            radius: 16,
            backgroundColor: Color(0xFF1E3A8A),
            child: Icon(Icons.person, size: 18, color: Colors.white),
          ),
        ],
      ),
    );
  }

  // --- SIDEBAR CONTENT (SHARED BY WEB & MOBILE DRAWER) ---
  Widget _buildSidebarContent() {
    return Column(
      children: [
        _buildSidebarHeader(),
        const Divider(color: Colors.white24, indent: 20, endIndent: 20),
        const SizedBox(height: 20),
        _sidebarItem(0, Icons.dashboard_rounded, "Overview"),
        const Spacer(),
        _sidebarItem(99, Icons.logout_rounded, "Logout", isLogout: true),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildSidebarHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 30),
      child: Column(
        children: [
          const Icon(Icons.auto_graph_rounded, color: Colors.white, size: 40),
          const SizedBox(height: 10),
          const Text("CLEAR GROW", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
          Text(widget.userRole, style: const TextStyle(color: Colors.white54, fontSize: 10)),
        ],
      ),
    );
  }

  Widget _sidebarItem(int index, IconData icon, String label, {bool isLogout = false}) {
    bool selected = _selectedIndex == index;
    return ListTile(
      onTap: isLogout ? _showLogoutDialog : () => setState(() => _selectedIndex = index),
      leading: Icon(icon, color: selected ? Colors.white : Colors.white60, size: 20),
      title: Text(label, style: TextStyle(color: selected ? Colors.white : Colors.white60, fontSize: 14)),
      tileColor: selected ? Colors.white.withOpacity(0.1) : Colors.transparent,
      contentPadding: const EdgeInsets.symmetric(horizontal: 25),
    );
  }

  // --- DASHBOARD CONTENT ---
  Widget _buildDashboardContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Quick Actions", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1E3A8A))),
        const SizedBox(height: 20),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: MediaQuery.of(context).size.width > 900 ? 3 : 2,
          crossAxisSpacing: 20,
          mainAxisSpacing: 20,
          childAspectRatio: 1.4,
          children: [
            _webActionCard("Kuri List", "Manage all groups", Icons.account_tree, Colors.indigo,
                    () => Navigator.push(context, MaterialPageRoute(builder: (_) => KuriListScreen(userId: widget.userId, userName: widget.userName, userRole: widget.userRole)))),
            _webActionCard("Staff Members", "Add or edit staff", Icons.people_alt, Colors.teal,
                    () => Navigator.push(context, MaterialPageRoute(builder: (_) => StaffManagementScreen(userId: widget.userId, userName: widget.userName, userRole: widget.userRole)))),
            _webActionCard("Expenses", "Track daily costs", Icons.wallet, Colors.redAccent,
                    () => Navigator.push(context, MaterialPageRoute(builder: (_) => ExpenseManagerWeb(userId: widget.userId, userName: widget.userName, userRole: widget.userRole)))),
            _webActionCard("Company", "Total Report", Icons.account_balance, Colors.greenAccent,
                    () => Navigator.push(context, MaterialPageRoute(builder: (_) => CompanyGlobalAuditWeb( userName: widget.userName, userRole: widget.userRole,)))),
          ],
        ),
      ],
    );
  }

  Widget _webActionCard(String title, String subtitle, IconData icon, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(15),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(15),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4))],
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 35),
            const SizedBox(height: 12),
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            Text(subtitle, style: const TextStyle(color: Colors.grey, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}