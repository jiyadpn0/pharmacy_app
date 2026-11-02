import 'package:flutter/material.dart';
import '../models/email_item.dart';
import '../services/gmail_service.dart';

class GmailInboxScreen extends StatefulWidget {
  const GmailInboxScreen({super.key});

  @override
  State<GmailInboxScreen> createState() => _GmailInboxScreenState();
}

class _GmailInboxScreenState extends State<GmailInboxScreen> {
  final GmailService _gmailService = GmailService();
  final TextEditingController _searchController = TextEditingController(
    text: GmailService.defaultSupplierFilterQuery,
  );

  UserAuthInfo? _user;
  List<EmailItem> _emails = [];
  bool _isLoading = false;
  String? _errorMessage;

  // Filter preset options
  String _selectedFilter = 'supplier'; // 'supplier', 'attachments', 'custom', 'all'

  @override
  void initState() {
    super.initState();
    _checkSilentSignIn();
  }

  Future<void> _checkSilentSignIn() async {
    final user = await _gmailService.signInSilently();
    if (user != null && mounted) {
      setState(() {
        _user = user;
      });
      _fetchEmails();
    }
  }

  Future<void> _handleSignIn() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final user = await _gmailService.signIn();
      if (!mounted) return;

      setState(() {
        _user = user;
      });

      if (user != null) {
        await _fetchEmails();
      } else {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  Future<void> _fetchEmails() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      String? query;
      if (_selectedFilter == 'supplier') {
        query = GmailService.defaultSupplierFilterQuery;
      } else if (_selectedFilter == 'attachments') {
        query = 'has:attachment (invoice OR bill OR purchase OR medicine)';
      } else if (_selectedFilter == 'custom') {
        query = _searchController.text.trim();
      } else {
        query = null; // All emails
      }

      final emails = await _gmailService.fetchRecentEmails(
        maxResults: 20,
        query: query,
      );

      if (!mounted) return;
      setState(() {
        _emails = emails;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  Future<void> _handleSignOut() async {
    await _gmailService.signOut();
    if (!mounted) return;
    setState(() {
      _user = null;
      _emails = [];
      _errorMessage = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gmail Supplier Inbox'),
        actions: [
          if (_user != null)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _fetchEmails,
              tooltip: 'Refresh Emails',
            ),
          if (_user != null)
            IconButton(
              icon: const Icon(Icons.logout),
              onPressed: _handleSignOut,
              tooltip: 'Sign Out',
            ),
        ],
      ),
      body: _user == null ? _buildSignInView() : _buildInboxView(),
    );
  }

  Widget _buildSignInView() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.mark_email_read, size: 80, color: Colors.blueAccent),
            const SizedBox(height: 24),
            const Text(
              'Gmail Supplier Mail Integration',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text(
              'Sign in with Google to view recent supplier and pharmacy invoice emails.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 24),
            if (_errorMessage != null) _buildDiagnosticErrorBox(),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              icon: const Icon(Icons.login),
              label: Text(_isLoading ? 'Signing in...' : 'Sign in with Google'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              ),
              onPressed: _isLoading ? null : _handleSignIn,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDiagnosticErrorBox() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, color: Colors.red),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _errorMessage!,
              style: TextStyle(color: Colors.red.shade900, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withAlpha(50),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                ChoiceChip(
                  label: const Text('Invoices & Suppliers Only'),
                  selected: _selectedFilter == 'supplier',
                  onSelected: (selected) {
                    if (selected) {
                      setState(() => _selectedFilter = 'supplier');
                      _fetchEmails();
                    }
                  },
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('With Invoice Attachments'),
                  selected: _selectedFilter == 'attachments',
                  onSelected: (selected) {
                    if (selected) {
                      setState(() => _selectedFilter = 'attachments');
                      _fetchEmails();
                    }
                  },
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('Custom Search Query'),
                  selected: _selectedFilter == 'custom',
                  onSelected: (selected) {
                    if (selected) {
                      setState(() => _selectedFilter = 'custom');
                    }
                  },
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('All Mails'),
                  selected: _selectedFilter == 'all',
                  onSelected: (selected) {
                    if (selected) {
                      setState(() => _selectedFilter = 'all');
                      _fetchEmails();
                    }
                  },
                ),
              ],
            ),
          ),
          if (_selectedFilter == 'custom') ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      hintText: 'e.g. from:medigenmedcare.com or "GREEN SPECIALITIES"',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _fetchEmails(),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _fetchEmails,
                  child: const Text('Search'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInboxView() {
    return Column(
      children: [
        // User Profile Header
        Container(
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withAlpha(102),
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
          child: Row(
            children: [
              CircleAvatar(
                backgroundImage:
                    _user?.photoUrl != null ? NetworkImage(_user!.photoUrl!) : null,
                child: _user?.photoUrl == null
                    ? Text(_user?.displayName[0].toUpperCase() ?? 'U')
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _user?.displayName ?? 'Connected User',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      _user?.email ?? '',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red.shade700,
                  side: BorderSide(color: Colors.red.shade300),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  minimumSize: const Size(0, 32),
                ),
                icon: const Icon(Icons.logout, size: 16),
                label: const Text('Logout', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                onPressed: _handleSignOut,
              ),
            ],
          ),
        ),

        // Filter & Search Bar
        _buildFilterBar(),
        const Divider(height: 1),

        // Mail List
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _errorMessage != null
                  ? Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _buildDiagnosticErrorBox(),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            icon: const Icon(Icons.refresh),
                            label: const Text('Retry Fetching Emails'),
                            onPressed: _fetchEmails,
                          ),
                        ],
                      ),
                    )
                  : _emails.isEmpty
                      ? const Center(
                          child: Text('No matching supplier emails found.'))
                      : RefreshIndicator(
                          onRefresh: _fetchEmails,
                          child: ListView.separated(
                            itemCount: _emails.length,
                            separatorBuilder: (ctx, i) => const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final email = _emails[index];
                              final isSupplier = email.from
                                      .toLowerCase()
                                      .contains('medigenmedcare.com') ||
                                  email.subject.toLowerCase().contains('invoice');

                              return ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: isSupplier
                                      ? Colors.blue.shade100
                                      : Colors.grey.shade200,
                                  child: Icon(
                                    isSupplier
                                        ? Icons.receipt_long
                                        : Icons.email_outlined,
                                    color: isSupplier ? Colors.blue : Colors.grey,
                                  ),
                                ),
                                title: Text(
                                  email.subject,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      email.from,
                                      maxLines: 1,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.black87,
                                      ),
                                    ),
                                    Text(
                                      email.snippet,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ],
                                ),
                                trailing: Text(
                                  email.date.length > 11
                                      ? email.date.substring(0, 11)
                                      : email.date,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: Colors.grey,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
        ),
      ],
    );
  }
}
