import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class MessagingPage extends StatelessWidget {
  const MessagingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Material(
            color: Theme.of(context).scaffoldBackgroundColor,
            child: TabBar(
              labelColor: Theme.of(context).colorScheme.primary,
              unselectedLabelColor: Theme.of(context).textTheme.bodySmall?.color,
              tabs: const [Tab(text: 'Friends'), Tab(text: 'Chats')],
            ),
          ),
          const Expanded(
            child: TabBarView(
              children: [
                FriendsTab(),
                Center(child: Text('Chats tab', style: TextStyle(fontSize: 18))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class FriendsTab extends StatefulWidget {
  const FriendsTab({super.key});

  @override
  State<FriendsTab> createState() => _FriendsTabState();
}

class _FriendsTabState extends State<FriendsTab> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>> _results = [];

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: const InputDecoration(
                    labelText: 'Search users by name or email',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) {
                    // Debounce input and call backend search
                    _debounce?.cancel();
                    _debounce = Timer(const Duration(milliseconds: 300), () => _performSearch(v));
                  },
                ),
              ),
              const SizedBox(width: 8),
              // Minimal search button triggers immediate search
              IconButton(
                icon: const Icon(Icons.search),
                onPressed: () => _performSearch(_searchController.text),
              ),
            ],
          ),
        ),
        // Placeholder ListView for results (empty now).
        Expanded(
          child: _results.isEmpty
              ? Center(child: Text(_searchController.text.isEmpty ? 'No results' : 'No matches'))
              : ListView.builder(
                  itemCount: _results.length,
                  itemBuilder: (context, index) {
                    final item = _results[index];
                    final account = item['accountName'] ?? '<no-name>';
                    final email = item['email'] ?? '';
                    return ListTile(
                      title: Text(account),
                      subtitle: Text(email),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Future<void> _performSearch(String q) async {
    final query = q.trim();
    if (query.isEmpty) {
      setState(() => _results = []);
      return;
    }

    try {
      final uri = Uri.parse('http://127.0.0.1:8000/users/search').replace(queryParameters: {'query': query});
      final resp = await http.get(uri);
      if (resp.statusCode == 200) {
        final data = json.decode(resp.body);
        if (data is List) {
          setState(() => _results = List<Map<String, dynamic>>.from(data));
          return;
        }
      }
      setState(() => _results = []);
    } catch (_) {
      setState(() => _results = []);
    }
  }
}
