import 'package:firestream/features/chat/screens/chatListScreen.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class UserDetailPage extends StatefulWidget {
  final String email;
  final String currentUserEmail;

  const UserDetailPage({
    super.key,
    required this.email,
    required this.currentUserEmail,
  });

  @override
  _UserDetailPageState createState() => _UserDetailPageState();
}

class _UserDetailPageState extends State<UserDetailPage> {
  late String email;
  late String currentUserEmail;

  @override
  void initState() {
    super.initState();
    email = widget.email;
    currentUserEmail = widget.currentUserEmail;
  }

  // Fetch user details from Firestore
  Future<Map<String, dynamic>?> _fetchUserDetails() async {
    var userDoc =
        await FirebaseFirestore.instance.collection('users').doc(email).get();
    return userDoc.exists ? userDoc.data() : null;
  }

  Future<bool> _isContactSaved(String email) async {
    try {
      DocumentSnapshot savedContactsDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUserEmail)
          .collection('contacts')
          .doc('savedContacts')
          .get();

      if (savedContactsDoc.exists) {
        List<dynamic> contactEmails = savedContactsDoc['contactEmails'] ?? [];
        return contactEmails.contains(email);
      }
      return false;
    } catch (e) {
      debugPrint("Error checking saved contact: $e");
      return false;
    }
  }

  Future<void> _addToContacts(BuildContext context) async {
    try {
      // Update UI immediately
      setState(() {});

      // Reference to the user's document
      DocumentReference userDocRef =
          FirebaseFirestore.instance.collection('users').doc(currentUserEmail);

      // Check if the "contacts" subcollection exists
      var contactsDoc =
          await userDocRef.collection('contacts').doc('savedContacts').get();

      if (!contactsDoc.exists) {
        // Create the "contacts" document if it doesn't exist
        await userDocRef.collection('contacts').doc('savedContacts').set({
          'contactEmails': [], // Initialize with an empty array
        });
      }

      // Add the email to the "contactEmails" array
      await userDocRef.collection('contacts').doc('savedContacts').update({
        'contactEmails': FieldValue.arrayUnion([email]),
      });

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("User added to your contacts.")),
      );

      // Update UI state after successful addition
      setState(() {});
    } catch (e) {
      // Handle errors
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to add contact: ${e.toString()}")),
      );
    }
  }

  Future<void> _addToBlockList(BuildContext context) async {
    try {
      // Update UI immediately
      setState(() {});

      // Reference to the user's document
      DocumentReference userDocRef =
          FirebaseFirestore.instance.collection('users').doc(currentUserEmail);

      // Check if the "contacts" subcollection exists
      var contactsDoc =
          await userDocRef.collection('contacts').doc('blockList').get();

      if (!contactsDoc.exists) {
        // Create the "contacts" document if it doesn't exist
        await userDocRef.collection('contacts').doc('blockList').set({
          'contactEmails': [], // Initialize with an empty array
        });
      }

      // Add the email to the "contactEmails" array
      await userDocRef.collection('contacts').doc('blockList').update({
        'contactEmails': FieldValue.arrayUnion([email]),
      });

      var chatSnapshot = await FirebaseFirestore.instance
          .collection('chats')
          .where('participants', arrayContains: currentUserEmail)
          .get();

      // Iterate over chat documents to find the chat with only the current user and the blocked user
      for (var doc in chatSnapshot.docs) {
        var participants = List<String>.from(doc['participants']);
        // Check if there are exactly two participants and the other one is the blocked email
        if (participants.length == 2 && participants.contains(email)) {
          // Delete the chat document if it only contains the current user and the blocked user
          await FirebaseFirestore.instance
              .collection('chats')
              .doc(doc.id)
              .delete();
          break; // Stop after deleting the chat
        }
      }

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("User added to blacklist.")),
      );
      // Update UI state after successful addition
      setState(() {});

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => const ChatListScreen(),
        ),
      );
    } catch (e) {
      // Handle errors
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text("Failed to adding in blacklist: ${e.toString()}")),
      );
    }
  }

  // Fetch eligible groups for the current user
  Future<List<QueryDocumentSnapshot>> _fetchEligibleGroups() async {
    var groupChats =
        await FirebaseFirestore.instance.collection('groupChats').get();
    return groupChats.docs.where((doc) {
      var addMembersBy = doc['AddMembersBy'];
      var participants = List<String>.from(doc['participants']);
      var admins = List<String>.from(doc['admins']);

      if (addMembersBy == "anyone") {
        return participants.contains(currentUserEmail);
      } else if (addMembersBy == "admin only") {
        return admins.contains(currentUserEmail) &&
            participants.contains(currentUserEmail);
      }
      return false;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("User Details"),
        backgroundColor: Colors.blueAccent,
      ),
      body: FutureBuilder<Map<String, dynamic>?>(
        future: _fetchUserDetails(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data == null) {
            return const Center(child: Text("User not found."));
          }

          final userDetails = snapshot.data!;
          return _buildUserDetails(context, userDetails);
        },
      ),
    );
  }

  // Build user details UI
  Widget _buildUserDetails(
      BuildContext context, Map<String, dynamic> userDetails) {
    final String profileUrl =
        userDetails['profilePic'] ?? "https://via.placeholder.com/150";
    final String username = userDetails['username'] ?? "Unknown User";

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Card(
        elevation: 10,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(25),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Profile picture with shadow and click-to-view functionality
              GestureDetector(
                onTap: () => _viewImage(context, profileUrl),
                child: CircleAvatar(
                  radius: 60,
                  backgroundImage: NetworkImage(profileUrl),
                  backgroundColor: Colors.transparent,
                ),
              ),
              const SizedBox(height: 20),
              // Username with a modern font and spacing
              Text(
                username,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              // Email address with subtle grey color and spacing
              Text(
                email,
                style: const TextStyle(
                  fontSize: 16,
                  color: Colors.grey,
                  fontStyle: FontStyle.italic,
                ),
              ),
              const SizedBox(height: 30),

              // Add to Group button with modern styling
              ElevatedButton.icon(
                onPressed: () => _showAddToGroupDialog(context),
                icon: const Icon(Icons.group_add, size: 20),
                label: const Text(
                  "Add to Group",
                  style: TextStyle(fontSize: 16),
                ),
                style: ElevatedButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: Colors.teal,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                  padding:
                      const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
                  elevation: 5,
                ),
              ),
              const SizedBox(height: 20),

              // Add to Contacts button using FutureBuilder
              FutureBuilder<bool>(
                future: _isContactSaved(email),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const CircularProgressIndicator();
                  }
                  if (snapshot.data == true) {
                    return ElevatedButton.icon(
                      onPressed: null, // Disabled
                      icon: const Icon(Icons.check, color: Colors.white),
                      label: const Text(
                        "Added to Contacts",
                        style: TextStyle(fontSize: 16),
                      ),
                      style: ElevatedButton.styleFrom(
                        foregroundColor: Colors.white,
                        backgroundColor: Colors.grey,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                        padding: const EdgeInsets.symmetric(
                            vertical: 12, horizontal: 20),
                        elevation: 2,
                      ),
                    );
                  } else {
                    return ElevatedButton.icon(
                      onPressed: () => _addToContacts(context),
                      icon: const Icon(Icons.person_add, size: 20),
                      label: const Text(
                        "Add to Contacts",
                        style: TextStyle(fontSize: 16),
                      ),
                      style: ElevatedButton.styleFrom(
                        foregroundColor: Colors.white,
                        backgroundColor: Colors.blue,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                        padding: const EdgeInsets.symmetric(
                            vertical: 12, horizontal: 20),
                        elevation: 5,
                      ),
                    );
                  }
                },
              ),
              const SizedBox(height: 20),

              // Add to Block List button with modern design
              ElevatedButton.icon(
                onPressed: () => _addToBlockList(context),
                icon: const Icon(Icons.block, size: 20),
                label: const Text(
                  "Add to Block List",
                  style: TextStyle(fontSize: 16),
                ),
                style: ElevatedButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: Colors.redAccent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                  padding:
                      const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
                  elevation: 5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

// Function to view the image in a larger view
  void _viewImage(BuildContext context, String imageUrl) {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Image.network(
              imageUrl,
              fit: BoxFit.contain,
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return Center(
                  child: CircularProgressIndicator(
                    value: loadingProgress.expectedTotalBytes != null
                        ? loadingProgress.cumulativeBytesLoaded /
                            (loadingProgress.expectedTotalBytes ?? 1)
                        : null,
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }



  // Show Add to Group dialog
  void _showAddToGroupDialog(BuildContext context) async {
    final eligibleGroups = await _fetchEligibleGroups();

    if (eligibleGroups.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No eligible groups available.")),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) {
        return _buildGroupSelectionDialog(context, eligibleGroups);
      },
    );
  }

// Build group selection dialog
  Widget _buildGroupSelectionDialog(
      BuildContext context, List<QueryDocumentSnapshot> eligibleGroups) {
    // Create a map to store initial selected state of groups
    List<bool> selectedGroups = eligibleGroups.map((group) {
      List<dynamic> participants = group['participants'] ?? [];
      return participants.contains(email);
    }).toList();

    return AlertDialog(
      title: const Text("Select Groups"),
      content: SizedBox(
        height: 300,
        width: double.maxFinite,
        child: ListView.builder(
          itemCount: eligibleGroups.length,
          itemBuilder: (context, index) {
            var group = eligibleGroups[index];
            String groupName =
                group['groupName'] ?? 'Unnamed Group'; // Group name
            String groupPhotoUrl =
                group['groupPhotoUrl'] ?? ''; // Group photo URL

            return StatefulBuilder(
              builder: (context, setState) {
                return CheckboxListTile(
                  value: selectedGroups[index],
                  onChanged: (value) {
                    setState(() {
                      selectedGroups[index] = value!;
                    });
                  },
                  title: Row(
                    children: [
                      // Group photo
                      groupPhotoUrl.isNotEmpty
                          ? CircleAvatar(
                              radius: 20,
                              backgroundImage: NetworkImage(groupPhotoUrl),
                            )
                          : const Icon(Icons.group, size: 40), // Default icon

                      const SizedBox(width: 10), // Space between photo and name

                      // Group name
                      Expanded(
                        child: Text(
                          groupName,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 16),
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("Cancel"),
        ),
        ElevatedButton(
          onPressed: () =>
              _addUserToSelectedGroups(context, eligibleGroups, selectedGroups),
          child: const Text("Update Selection"),
        ),
      ],
    );
  }

// Add or remove user to/from selected groups
  Future<void> _addUserToSelectedGroups(
      BuildContext context,
      List<QueryDocumentSnapshot> eligibleGroups,
      List<bool> selectedGroups) async {
    for (int i = 0; i < eligibleGroups.length; i++) {
      var group = eligibleGroups[i];
      String groupId = group.id;
      List<dynamic> participants = group['participants'] ?? [];
      List<dynamic> admins = group['admins'] ?? [];

      // If the group is deselected but the user is currently in participants/admins, remove them
      if (!selectedGroups[i]) {
        if (participants.contains(email)) {
          participants.remove(email);
        }
        if (admins.contains(email)) {
          admins.remove(email);
        }
      }

      // If the group is selected and the user is not already in participants, add them
      if (selectedGroups[i] && !participants.contains(email)) {
        participants.add(email);
      }

      // Update the group document in Firestore
      await FirebaseFirestore.instance
          .collection('groupChats')
          .doc(groupId)
          .update({
        'participants': participants,
        'admins': admins,
      });
    }

    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Groups updated successfully.")),
    );
  }
}
