import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firestream/features/chat/screens/chatListScreen.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class GroupDetailsPage extends StatefulWidget {
  final String groupName;
  final String? groupPhotoUrl;
  final String chatId;

  const GroupDetailsPage({
    super.key,
    required this.groupName,
    this.groupPhotoUrl,
    required this.chatId,
  });

  @override
  _GroupDetailsPageState createState() => _GroupDetailsPageState();
}

class _GroupDetailsPageState extends State<GroupDetailsPage> {
  String? currentUserEmail;
  bool settingOnlyAdmin = false;

  bool currentUserIsAdmin = false;

  @override
  void initState() {
    super.initState();
    fetchCurrentUserEmail();
  }

  Future<void> fetchCurrentUserEmail() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      currentUserEmail = prefs.getString('userEmail');
    });
  }

  Future<bool> checkIfCurrentUserIsAdmin(String currentUserEmail) async {
    try {
      // Fetch the group document
      DocumentSnapshot groupDoc = await FirebaseFirestore.instance
          .collection('groupChats')
          .doc(widget.chatId) // You can dynamically set the group ID
          .get();

      // Check if the group document exists
      if (groupDoc.exists) {
        // Get the list of admins in the group
        List<dynamic> admins =
            groupDoc['admins']; // Assuming 'admin' is an array

        // Check if the current user's email is in the admin list
        return admins.contains(currentUserEmail);
      } else {
        return false; // Group document does not exist
      }
    } catch (e) {
      print("Error checking admin status: $e");
      return false;
    }
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

  Future<void> _addParticipantsToThisGroups() async {
    try {
      // Fetch group document to check AddMembersBy and current user's role
      DocumentSnapshot groupDoc = await FirebaseFirestore.instance
          .collection('groupChats')
          .doc(widget.chatId)
          .get();

      if (!groupDoc.exists) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Group does not exist.")),
        );
        return;
      }

      String addMembersBy =
          groupDoc['AddMembersBy'] ?? 'anyone'; // Default to 'anyone'
      List<String> admins =
          (groupDoc['admins'] as List<dynamic>?)?.cast<String>() ?? [];
      List<String> participants =
          (groupDoc['participants'] as List<dynamic>?)?.cast<String>() ?? [];

      // Check if current user is an admin if AddMembersBy = 'admin only'
      if (addMembersBy == 'admin only' && !admins.contains(currentUserEmail)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("You cannot add members, admin only.")),
        );
        return;
      }

      // Fetch current user's saved contacts
      DocumentSnapshot contactsDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUserEmail)
          .collection('contacts')
          .doc('savedContacts')
          .get();

      // Check if contacts document exists and has emails
      if (!contactsDoc.exists ||
          contactsDoc['contactEmails'] == null ||
          (contactsDoc['contactEmails'] as List<dynamic>).isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text("You haven't any contacts to add in the group.")),
        );
        return;
      }

      List<String> contactEmails =
          (contactsDoc['contactEmails'] as List<dynamic>).cast<String>();

      // Fetch user details for all contact emails
      QuerySnapshot userQuery = await FirebaseFirestore.instance
          .collection('users')
          .where(FieldPath.documentId, whereIn: contactEmails)
          .get();

      List<Map<String, dynamic>> userList = userQuery.docs.map((doc) {
        return {
          'email': doc.id,
          'username': doc['username'] ?? 'Unknown User',
          'profilePic': doc['profilePic'] ?? '',
          'isSelected': participants.contains(doc.id),
        };
      }).toList();

      // Show selection UI
      bool isUpdated = (await showModalBottomSheet<bool>(
            context: context,
            isScrollControlled: true,
            builder: (BuildContext context) {
              return StatefulBuilder(
                builder: (context, setState) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(height: 10),
                        const Text(
                          "Add/Remove Participants",
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const Divider(),
                        Expanded(
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: userList.length,
                            itemBuilder: (context, index) {
                              var user = userList[index];
                              return CheckboxListTile(
                                value: user['isSelected'],
                                onChanged: (bool? value) {
                                  setState(() {
                                    user['isSelected'] = value ?? false;
                                  });
                                },
                                title: Row(
                                  children: [
                                    user['profilePic'].isNotEmpty
                                        ? CircleAvatar(
                                            backgroundImage: NetworkImage(
                                                user['profilePic']),
                                          )
                                        : const CircleAvatar(
                                            child: Icon(Icons.person),
                                          ),
                                    const SizedBox(width: 10),
                                    Text(user['username']),
                                  ],
                                ),
                                subtitle: Text(user['email']),
                              );
                            },
                          ),
                        ),
                        ElevatedButton(
                          onPressed: () async {
                            // Update participants and admins in Firestore
                            List<String> selectedEmails = userList
                                .where((user) => user['isSelected'])
                                .map((user) => user['email'] as String)
                                .toList();

                            List<String> deselectedEmails = userList
                                .where((user) => !user['isSelected'])
                                .map((user) => user['email'] as String)
                                .toList();

                            // Add selected emails to participants
                            await FirebaseFirestore.instance
                                .collection('groupChats')
                                .doc(widget.chatId)
                                .update({
                              'participants':
                                  FieldValue.arrayUnion(selectedEmails),
                            });

                            // Remove deselected emails from participants and admins
                            await FirebaseFirestore.instance
                                .collection('groupChats')
                                .doc(widget.chatId)
                                .update({
                              'participants':
                                  FieldValue.arrayRemove(deselectedEmails),
                              'admins':
                                  FieldValue.arrayRemove(deselectedEmails),
                            });

                            Navigator.pop(context, true);

                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text(
                                      "Participants updated successfully.")),
                            );
                          },
                          child: const Text("Save"),
                        ),
                        const SizedBox(height: 10),
                      ],
                    ),
                  );
                },
              );
            },
          )) ??
          false; // Default to false if null

      // Check if changes were made and update the UI state
      if (isUpdated) {
        setState(() {
          // Trigger a refresh or state update here
          print("Participants have been updated.");
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e")),
      );
    }
  }

  void showProfilePicture(String? photoUrl, String userName) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            photoUrl != null && photoUrl.isNotEmpty
                ? Image.network(photoUrl)
                : const Icon(Icons.person, size: 100),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(userName, style: const TextStyle(fontSize: 20)),
            ),
          ],
        ),
      ),
    );
  }

  void deleteCurrentUser(String? email) async {
    if (email == null || email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("Email is null or empty. Cannot proceed.")),
      );
      return;
    }

    bool? confirmation = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Confirm Deletion"),
        content: Text("Are you sure you want to delete $email from the group?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Delete"),
          ),
        ],
      ),
    );

    if (confirmation == true) {
      try {
        var groupDoc = FirebaseFirestore.instance
            .collection('groupChats')
            .doc(widget.chatId);

        DocumentSnapshot groupData = await groupDoc.get();

        if (!groupData.exists) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Group document does not exist.")),
          );
          return;
        }

        List<dynamic> admins = List<dynamic>.from(groupData['admins'] ?? []);
        List<dynamic> participants =
            List<dynamic>.from(groupData['participants'] ?? []);

        // Remove email from the lists
        bool adminRemoved = admins.remove(email);
        bool participantRemoved = participants.remove(email);

        if (!adminRemoved && !participantRemoved) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text("Email not found in admins or participants.")),
          );
          return;
        }

        // Update the Firestore document
        await groupDoc.update({
          'admins': admins,
          'participants': participants,
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("User removed successfully.")),
        );

        setState(() {}); // Refresh UI

        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => const ChatListScreen(),
          ),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error removing user: $e")),
        );
      }
    }
  }

  void deleteUser(String email) async {
    bool? confirmation = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Confirm Deletion"),
        content: Text("Are you sure you want to delete $email from the group?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Delete"),
          ),
        ],
      ),
    );

    if (confirmation == true) {
      var groupDoc = FirebaseFirestore.instance
          .collection('groupChats')
          .doc(widget.chatId);
      DocumentSnapshot groupData = await groupDoc.get();

      List<String> admins = List<String>.from(groupData['admins'] ?? []);
      List<String> participants =
          List<String>.from(groupData['participants'] ?? []);

      if (admins.contains(email)) {
        admins.remove(email);
      }
      if (participants.contains(email)) {
        participants.remove(email);
      }

      await groupDoc.update({'admins': admins, 'participants': participants});
      setState(() {}); // Refresh UI
    }
  }

  void makeAdmin(String email) async {
    bool? confirmation = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Make Admin"),
        content: Text("Are you sure you want to make $email an admin?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Confirm"),
          ),
        ],
      ),
    );

    if (confirmation == true) {
      var groupDoc = FirebaseFirestore.instance
          .collection('groupChats')
          .doc(widget.chatId);
      DocumentSnapshot groupData = await groupDoc.get();

      List<String> admins = List<String>.from(groupData['admins'] ?? []);

      if (!admins.contains(email)) {
        admins.add(email);
        await groupDoc.update({'admins': admins});
        setState(() {}); // Refresh UI
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("$email is already an admin.")),
        );
      }
    }
  }

  void removeAdmin(String email) async {
    bool? confirmation = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Remove Admin"),
        content: Text("Are you sure you want to remove $email as admin?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Confirm"),
          ),
        ],
      ),
    );

    if (confirmation == true) {
      var groupDoc = FirebaseFirestore.instance
          .collection('groupChats')
          .doc(widget.chatId);
      DocumentSnapshot groupData = await groupDoc.get();

      List<String> admins = List<String>.from(groupData['admins'] ?? []);

      if (admins.contains(email)) {
        admins.remove(email);
        await groupDoc.update({'admins': admins});
        setState(() {}); // Refresh UI
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("$email is not an admin.")),
        );
      }
    }
  }

  void createChatWithUser(String email) async {
    String chatId = await createChat(currentUserEmail!, email);
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
        if (deletedBy.contains(currentUserEmail!)) {
          await FirebaseFirestore.instance
              .collection('chats')
              .doc(existingChatDoc.id)
              .update({
            'deletedBy': FieldValue.arrayRemove([currentUserEmail!]),
          });
        }
        return existingChatDoc.id;
      }
    } catch (e) {
      showSnackbar("Error creating chat: $e");
      return "";
    }
  }

  void showOptionsBottomSheet(BuildContext context, String email, bool isAdmin,
      bool isCurrentUser, bool isCurrentUserAdmin) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isCurrentUser)
            ListTile(
              leading: const Icon(Icons.exit_to_app, color: Colors.red),
              title: const Text('Remove'),
              onTap: () {
                // Remove yourself logic
                Navigator.pop(context);
                deleteCurrentUser(currentUserEmail!);
              },
            ),
          if (!isCurrentUser)
            ListTile(
              leading: const Icon(Icons.message, color: Colors.blue),
              title: const Text('Message'),
              onTap: () {
                Navigator.pop(context);
                // Handle message option
                createChatWithUser(email);
              },
            ),
          if (!isCurrentUser && isCurrentUserAdmin && isAdmin)
            ListTile(
              leading: const Icon(Icons.remove_circle, color: Colors.orange),
              title: const Text('Remove Admin'),
              onTap: () {
                Navigator.pop(context);
                removeAdmin(email);
              },
            ),
          if (!isCurrentUser && isCurrentUserAdmin && !isAdmin)
            ListTile(
              leading: const Icon(Icons.person_add, color: Colors.green),
              title: const Text('Make Admin'),
              onTap: () {
                Navigator.pop(context);
                makeAdmin(email);
              },
            ),
          if (!isCurrentUser &&
              isCurrentUserAdmin &&
              (!settingOnlyAdmin || isAdmin))
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('Delete'),
              onTap: () {
                Navigator.pop(context);
                deleteUser(email);
              },
            ),
        ],
      ),
    );
  }

  void _viewImage(BuildContext context) {
    // Show the image in a dialog or modal
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          child: SizedBox(
            width: double.infinity,
            height: double.infinity,
            child: Image.network(widget.groupPhotoUrl!),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Group Details'),
        backgroundColor: Colors.blueAccent,
      ),
      body: currentUserEmail == null
          ? const Center(child: CircularProgressIndicator())
          : FutureBuilder<DocumentSnapshot>(
              future: FirebaseFirestore.instance
                  .collection('groupChats')
                  .doc(widget.chatId)
                  .get(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                var groupData = snapshot.data!;
                List<String> admins =
                    List<String>.from(groupData['admins'] ?? []);
                List<String> participants =
                    List<String>.from(groupData['participants'] ?? []);

                Set<String> allUsers = {
                  currentUserEmail!,
                  ...admins,
                  ...participants,
                };

                return FutureBuilder<QuerySnapshot>(
                  future: FirebaseFirestore.instance
                      .collection('users')
                      .where(FieldPath.documentId, whereIn: allUsers.toList())
                      .get(),
                  builder: (context, userSnapshot) {
                    if (!userSnapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    Map<String, dynamic> userMap = {
                      for (var doc in userSnapshot.data!.docs)
                        doc.id: doc.data()
                    };

                    List<String> sortedParticipants = [
                      currentUserEmail!,
                      ...admins.where((email) => email != currentUserEmail),
                      ...participants.where((email) =>
                          email != currentUserEmail && !admins.contains(email)),
                    ];

                    return ListView(
                      padding: const EdgeInsets.all(8.0),
                      children: [
                        Center(
                          child: GestureDetector(
                            onTap: () {
                              // If there is a group photo URL, show the image in a dialog
                              if (widget.groupPhotoUrl != null &&
                                  widget.groupPhotoUrl!.isNotEmpty) {
                                _viewImage(context);
                              }
                            },
                            child: widget.groupPhotoUrl != null &&
                                    widget.groupPhotoUrl!.isNotEmpty
                                ? CircleAvatar(
                                    radius: 50,
                                    backgroundImage:
                                        NetworkImage(widget.groupPhotoUrl!),
                                  )
                                : const CircleAvatar(
                                    radius: 50,
                                    backgroundColor: Colors.grey,
                                    child:
                                        Icon(Icons.group, color: Colors.white),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Center(
                          child: Text(
                            widget.groupName,
                            style: const TextStyle(
                                fontSize: 24, fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              "Participants",
                              style: TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.w600),
                            ),
                            IconButton(
                              onPressed: () {
                                // Add participants logic here
                                _addParticipantsToThisGroups();
                              },
                              icon: const Icon(Icons.add, color: Colors.blue),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: sortedParticipants.length,
                          itemBuilder: (context, index) {
                            String email = sortedParticipants[index];
                            var userData = userMap[email] ?? {};

                            String userName =
                                userData['username'] ?? 'Unknown User';
                            String userPhotoUrl = userData['profilePic'] ?? '';
                            bool isAdmin = admins.contains(email);
                            bool isCurrentUser = email == currentUserEmail;

                            return GestureDetector(
                              // onLongPress: () => showOptionsBottomSheet(
                              //     context, email, isAdmin, isCurrentUser),

                              onLongPress: () async {
                                // Assuming you already have the currentUserEmail
                                currentUserIsAdmin =
                                    await checkIfCurrentUserIsAdmin(
                                        currentUserEmail!);

                                // Call the bottom sheet with the required parameters
                                showOptionsBottomSheet(
                                  context,
                                  email,
                                  isAdmin, // You may already have this variable, or you can fetch it similarly
                                  isCurrentUser,
                                  currentUserIsAdmin,
                                );
                              },

                              child: Card(
                                elevation: 2,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: ListTile(
                                  leading: GestureDetector(
                                    onTap: () => showProfilePicture(
                                        userPhotoUrl, userName),
                                    child: userPhotoUrl.isNotEmpty
                                        ? CircleAvatar(
                                            backgroundImage:
                                                NetworkImage(userPhotoUrl),
                                          )
                                        : const CircleAvatar(
                                            child: Icon(Icons.person)),
                                  ),
                                  title: Row(
                                    children: [
                                      Text(
                                        userName,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w600),
                                      ),
                                      if (isCurrentUser)
                                        const Padding(
                                          padding: EdgeInsets.only(left: 8.0),
                                          child: Text(
                                            "(You)",
                                            style: TextStyle(
                                                fontStyle: FontStyle.italic),
                                          ),
                                        ),
                                    ],
                                  ),
                                  subtitle: Row(
                                    children: [
                                      Text(email),
                                      if (isAdmin)
                                        const Padding(
                                          padding: EdgeInsets.only(left: 8.0),
                                          child: Chip(
                                            label: Text(
                                              'Admin',
                                              style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 12),
                                            ),
                                            backgroundColor: Colors.red,
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.all(
                                                  Radius.circular(8)),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    );
                  },
                );
              },
            ),
    );
  }
}
