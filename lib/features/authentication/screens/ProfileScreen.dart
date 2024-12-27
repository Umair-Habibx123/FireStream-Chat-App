import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firestream/features/authentication/screens/reset_password_screen.dart';
import 'package:firestream/features/authentication/screens/signin_screen.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  _ProfileScreenState createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  late String _photoURL;
  late String _username;
  late String _email;
  final _usernameController = TextEditingController();
  bool _isLoading = true; // Track loading state

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    final user = _auth.currentUser;

    if (user != null) {
      setState(() {
        _photoURL = prefs.getString('userPhoto') ?? '';
        _username = prefs.getString('userName') ?? '';
        _email = prefs.getString('userEmail') ?? '';
        _usernameController.text = _username;
        _isLoading = false; // Set loading to false after loading data
      });
    }
  }

  Future<void> _updateUsername() async {
    final newUsername = _usernameController.text.trim();
    if (newUsername.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();

    await FirebaseFirestore.instance
        .collection('users')
        .doc(_email)
        .update({'username': newUsername});

    await prefs.setString('userName', newUsername);

    setState(() {
      _username = newUsername;
    });
  }

  Future<void> _updateProfilePic() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);

    if (pickedFile != null) {
      setState(() {
        _isLoading = true; // Set loading to true while uploading
      });

      final prefs = await SharedPreferences.getInstance();
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('profile_pictures/${"$_email profile_pic"}.jpg');

      await storageRef.putFile(File(pickedFile.path));

      final downloadUrl = await storageRef.getDownloadURL();

      await FirebaseFirestore.instance
          .collection('users')
          .doc(_email)
          .update({'profilePic': downloadUrl});

      await prefs.setString('userPhoto', downloadUrl);

      setState(() {
        _photoURL = downloadUrl; // Use the download URL
        _isLoading = false; // Set loading to false after upload
      });
    }
  }

  Future<void> _updatePassword() async {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => const ResetPasswordScreen()),
    );
  }

  Future<void> _logout() async {
    // Sign out from Firebase
    await _auth.signOut();

    // Explicitly sign out from Google to clear cached credentials
    GoogleSignIn googleSignIn = GoogleSignIn();
    await googleSignIn.signOut();

    // Clear shared preferences if needed
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear(); // Clear shared preferences

    // Navigate to the login screen
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => const LoginScreen()),
      (Route<dynamic> route) => false,
    );
  }

  Future<void> _editContacts() async {
    // Navigate to Edit Contacts Screen
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const EditContactsScreen(),
      ),
    );
  }

  Future<void> _editBlocklist() async {
    // Navigate to Edit Blocklist Screen
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const EditBlocklistScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        backgroundColor: Colors.blueAccent,
        elevation: 4,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _isLoading
                    ? const CircularProgressIndicator() // Show loading indicator if loading
                    : CircleAvatar(
                        backgroundImage: NetworkImage(_photoURL),
                        radius: 40, // Adjust the radius as needed
                      ),
                IconButton(
                  icon: const Icon(Icons.edit),
                  onPressed: () {
                    _updateProfilePic(); // Call the updated function for profile pic upload
                  },
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              _username,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            Text(
              _email,
              style: const TextStyle(fontSize: 18, color: Colors.grey),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: ListView(
                children: [
                  ListTile(
                    title: const Text('Edit Username'),
                    trailing: const Icon(Icons.arrow_forward_ios),
                    onTap: () {
                      showDialog(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Edit Username'),
                          content: TextField(
                            controller: _usernameController,
                            decoration: const InputDecoration(
                              labelText: 'New Username',
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () {
                                _updateUsername();
                                Navigator.of(context).pop();
                              },
                              child: const Text('Update'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(),
                              child: const Text('Cancel'),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  ListTile(
                    title: const Text('Edit Password'),
                    trailing: const Icon(Icons.arrow_forward_ios),
                    onTap: () {
                      _updatePassword();
                    },
                  ),
                  ListTile(
                    title: const Text('Edit Contacts'),
                    trailing: const Icon(Icons.arrow_forward_ios),
                    onTap: _editContacts,
                  ),
                  ListTile(
                    title: const Text('Edit Blocklist'),
                    trailing: const Icon(Icons.arrow_forward_ios),
                    onTap: _editBlocklist,
                  ),
                  ListTile(
                    title: const Text('Logout'),
                    trailing: const Icon(Icons.logout),
                    onTap: _logout,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class EditContactsScreen extends StatefulWidget {
  const EditContactsScreen({super.key});

  @override
  _EditContactsScreenState createState() => _EditContactsScreenState();
}

class _EditContactsScreenState extends State<EditContactsScreen> {
  final String _currentUserEmail =
      FirebaseAuth.instance.currentUser?.email ?? '';
  List<Map<String, dynamic>> _contacts = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  Future<void> _loadContacts() async {
    try {
      final savedContactsDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUserEmail)
          .collection('contacts')
          .doc('savedContacts')
          .get();

      if (savedContactsDoc.exists) {
        List<dynamic> contactEmails = savedContactsDoc['contactEmails'] ?? [];
        List<Map<String, dynamic>> contactsDetails = [];

        // Fetch additional user details for each contact email
        for (String email in contactEmails) {
          final userDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(email)
              .get();

          if (userDoc.exists) {
            final userData = userDoc.data();
            contactsDetails.add({
              'email': email,
              'username': userData?['username'] ?? 'Unknown',
              'profilePic': userData?['profilePic'] ?? '',
            });
          }
        }

        setState(() {
          _contacts = contactsDetails;
          _isLoading = false;
        });
      } else {
        setState(() {
          _contacts = [];
          _isLoading = false;
        });
      }
    } catch (e) {
      print("Error loading contacts: $e");
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _deleteContact(String email) async {
    try {
      setState(() {
        _isLoading = true;
      });

      final savedContactsDocRef = FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUserEmail)
          .collection('contacts')
          .doc('savedContacts');

      final savedContactsDoc = await savedContactsDocRef.get();

      if (savedContactsDoc.exists) {
        List<dynamic> contactEmails = savedContactsDoc['contactEmails'] ?? [];
        contactEmails.remove(email);

        await savedContactsDocRef.update({'contactEmails': contactEmails});

        setState(() {
          _contacts = contactEmails.map((email) => {'email': email}).toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      print("Error deleting contact: $e");
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Edit Contacts"),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _contacts.isEmpty
              ? const Center(child: Text("No contacts found."))
              : ListView.builder(
                  itemCount: _contacts.length,
                  itemBuilder: (context, index) {
                    final contact = _contacts[index];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundImage: NetworkImage(contact['profilePic']),
                      ),
                      title: Text(contact['username']),
                      subtitle: Text(contact['email']),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _deleteContact(contact['email']),
                      ),
                    );
                  },
                ),
    );
  }
}

class EditBlocklistScreen extends StatefulWidget {
  const EditBlocklistScreen({super.key});

  @override
  _EditBlocklistScreenState createState() => _EditBlocklistScreenState();
}

class _EditBlocklistScreenState extends State<EditBlocklistScreen> {
  final String _currentUserEmail =
      FirebaseAuth.instance.currentUser?.email ?? '';
  List<Map<String, dynamic>> _blocklist = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadBlocklist();
  }

  Future<void> _loadBlocklist() async {
    try {
      final blocklistDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUserEmail)
          .collection('contacts')
          .doc('blockList')
          .get();

      if (blocklistDoc.exists) {
        List<dynamic> blocklist = blocklistDoc['contactEmails'] ?? [];
        List<Map<String, dynamic>> blocklistDetails = [];

        // Fetch additional user details for each blocked email
        for (String email in blocklist) {
          final userDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(email)
              .get();

          if (userDoc.exists) {
            final userData = userDoc.data();
            blocklistDetails.add({
              'email': email,
              'username': userData?['username'] ?? 'Unknown',
              'profilePic': userData?['profilePic'] ?? '',
            });
          }
        }

        setState(() {
          _blocklist = blocklistDetails;
          _isLoading = false;
        });
      } else {
        setState(() {
          _blocklist = [];
          _isLoading = false;
        });
      }
    } catch (e) {
      print("Error loading blocklist: $e");
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _deleteFromBlocklist(String email) async {
    try {
      setState(() {
        _isLoading = true;
      });

      final blocklistDocRef = FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUserEmail)
          .collection('contacts')
          .doc('blockList');

      final blocklistDoc = await blocklistDocRef.get();

      if (blocklistDoc.exists) {
        List<dynamic> blocklist = blocklistDoc['contactEmails'] ?? [];
        blocklist.remove(email);

        await blocklistDocRef.update({'contactEmails': blocklist});

        setState(() {
          _blocklist.removeWhere((contact) => contact['email'] == email);
          _isLoading = false;
        });
      }
    } catch (e) {
      print("Error deleting from blocklist: $e");
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Edit Blocklist"),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _blocklist.isEmpty
              ? const Center(child: Text("No blocked contacts found."))
              : ListView.builder(
                  itemCount: _blocklist.length,
                  itemBuilder: (context, index) {
                    final blockedContact = _blocklist[index];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundImage:
                            NetworkImage(blockedContact['profilePic']),
                      ),
                      title: Text(blockedContact['username']),
                      subtitle: Text(blockedContact['email']),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () =>
                            _deleteFromBlocklist(blockedContact['email']),
                      ),
                    );
                  },
                ),
    );
  }
}
