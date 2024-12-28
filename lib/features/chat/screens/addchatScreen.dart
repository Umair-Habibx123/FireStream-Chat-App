import 'package:firestream/features/chat/screens/ChatListScreen.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:validators/validators.dart';

class AddNewChatScreen extends StatefulWidget {
  const AddNewChatScreen({super.key});

  @override
  _AddNewChatScreenState createState() => _AddNewChatScreenState();
}

class _AddNewChatScreenState extends State<AddNewChatScreen> {
  final TextEditingController _emailController = TextEditingController();
  String _searchResult = "";
  String _currentUserEmail = "";
  List<Map<String, dynamic>> _contacts = [];
  List<Map<String, dynamic>> _searchResults = [];

  @override
  void initState() {
    super.initState();
    _loadCurrentUserEmail();
    _emailController.addListener(_searchUser);
  }

  @override
  void dispose() {
    _emailController.removeListener(_searchUser);
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentUserEmail() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      _currentUserEmail = prefs.getString('userEmail') ?? '';
    });
    await _loadContacts();
  }

  void showSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.redAccent,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // Future<void> _loadContacts() async {
  //   try {
  //     DocumentSnapshot savedContactsDoc = await FirebaseFirestore.instance
  //         .collection('users')
  //         .doc(_currentUserEmail)
  //         .collection('contacts')
  //         .doc('savedContacts')
  //         .get();

  //     if (savedContactsDoc.exists) {
  //       List<dynamic> contactEmails = savedContactsDoc['contactEmails'] ?? [];
  //       List<Map<String, dynamic>> contacts = [];

  //       for (String email in contactEmails) {
  //         DocumentSnapshot userDoc = await FirebaseFirestore.instance
  //             .collection('users')
  //             .doc(email)
  //             .get();
  //         if (userDoc.exists) {
  //           contacts.add({
  //             'email': email,
  //             'username': userDoc['username'],
  //             'profilePic': userDoc['profilePic'],
  //           });
  //         }
  //       }

  //       setState(() {
  //         _contacts = contacts;
  //       });
  //     }
  //   } catch (e) {
  //     showSnackbar("Error loading contacts: $e");
  //   }
  // }

  Future<void> _loadContacts() async {
    try {
      // Fetch saved contacts
      DocumentSnapshot savedContactsDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUserEmail)
          .collection('contacts')
          .doc('savedContacts')
          .get();

      // Fetch blocklist
      DocumentSnapshot blockListDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUserEmail)
          .collection('contacts')
          .doc('blockList')
          .get();

      if (savedContactsDoc.exists) {
        List<dynamic> contactEmails = savedContactsDoc['contactEmails'] ?? [];
        List<dynamic> blockListEmails =
            blockListDoc.exists ? blockListDoc['contactEmails'] ?? [] : [];

        List<Map<String, dynamic>> contacts = [];

        for (String email in contactEmails) {
          // Skip contacts in blocklist
          if (blockListEmails.contains(email)) continue;

          DocumentSnapshot userDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(email)
              .get();

          if (userDoc.exists) {
            contacts.add({
              'email': email,
              'username': userDoc['username'],
              'profilePic': userDoc['profilePic'],
            });
          }
        }

        setState(() {
          _contacts = contacts;
        });
      }
    } catch (e) {
      showSnackbar("Error loading contacts: $e");
    }
  }

  void _searchUser() async {
    String email = _emailController.text.trim();

    if (email.isEmpty) {
      setState(() {
        _searchResults = [];
        _searchResult = "";
      });
      return;
    }

    if (!isEmail(email)) {
      setState(() {
        _searchResult = "Invalid email format";
      });
      return;
    }

    if (email == _currentUserEmail) {
      setState(() {
        _searchResult = "You cannot chat with yourself";
      });
      return;
    }

    try {
      DocumentSnapshot userDoc =
          await FirebaseFirestore.instance.collection('users').doc(email).get();

      if (userDoc.exists) {
        // Check blocklist
        DocumentSnapshot blocklistDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(_currentUserEmail)
            .collection('contacts')
            .doc('blockList')
            .get();

        List<dynamic> blocklist =
            blocklistDoc.exists ? blocklistDoc['contactEmails'] ?? [] : [];
        if (blocklist.contains(email)) {
          setState(() {
            _searchResult = "User is in your blocklist.";
            _searchResults = [];
          });
          return;
        }

        setState(() {
          _searchResults = [
            {
              'email': email,
              'username': userDoc['username'],
              'profilePic': userDoc['profilePic'],
            }
          ];
          _searchResult = "";
        });
      } else {
        setState(() {
          _searchResult = "No user found with that email";
          _searchResults = [];
        });
      }
    } catch (e) {
      showSnackbar("Error searching user: $e");
    }
  }

  void _createChatWithUser(String email) async {
    String chatId = await createChat(_currentUserEmail, email);
    if (chatId.isNotEmpty) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const ChatListScreen()),
      );
    } else {
      showSnackbar("Failed to create chat");
    }
  }

  Future<String> createChat(String email1, String email2) async {
    try {
      var chatSnapshot = await FirebaseFirestore.instance
          .collection('chats')
          .where('participants', arrayContains: email1)
          .get();

      QueryDocumentSnapshot<Map<String, dynamic>>? existingChatDoc;
      for (var doc in chatSnapshot.docs) {
        var participants = doc['participants'] as List<dynamic>;
        if (participants.contains(email2) && participants.length == 2) {
          existingChatDoc = doc;
          break;
        }
      }

      if (existingChatDoc == null) {
        DocumentReference chatRef =
            await FirebaseFirestore.instance.collection('chats').add({
          'participants': [email1, email2],
          'lastMessage': '',
          'chatType': 'individual',
          'timestamp': FieldValue.serverTimestamp(),
          'deletedBy': [],
        });
        return chatRef.id;
      } else {
        List<dynamic> deletedBy = existingChatDoc['deletedBy'] ?? [];
        if (deletedBy.contains(_currentUserEmail)) {
          await FirebaseFirestore.instance
              .collection('chats')
              .doc(existingChatDoc.id)
              .update({
            'deletedBy': FieldValue.arrayRemove([_currentUserEmail]),
          });
        }
        return existingChatDoc.id;
      }
    } catch (e) {
      showSnackbar("Error creating chat: $e");
      return "";
    }
  }

  @override
  Widget build(BuildContext context) {
    final listToShow =
        _emailController.text.isEmpty ? _contacts : _searchResults;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Add New Chat"),
        backgroundColor: Colors.blueAccent,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Card(
              elevation: 5,
              child: Column(
                children: [
                  TextField(
                    controller: _emailController,
                    decoration: const InputDecoration(
                      labelText: "Enter Email",
                      suffixIcon: Icon(Icons.search),
                    ),
                  ),
                  if (_searchResult.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(
                        _searchResult,
                        style: const TextStyle(
                            color: Colors.redAccent, fontSize: 14),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: ListView.builder(
                itemCount: listToShow.length,
                itemBuilder: (context, index) {
                  final user = listToShow[index];
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundImage: NetworkImage(user['profilePic'] ?? ''),
                    ),
                    title: Text(user['username']),
                    subtitle: Text(user['email']),
                    onTap: () => _createChatWithUser(user['email']),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
