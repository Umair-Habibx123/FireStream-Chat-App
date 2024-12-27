import 'package:firebase_storage/firebase_storage.dart';
import 'package:firestream/features/chat/screens/GroupSettingsScreen.dart';
import 'package:firestream/features/chat/screens/addGroupChatScreen.dart';
import 'package:firestream/features/chat/screens/addchatScreen.dart';
import 'package:firestream/features/chat/screens/chatScreen.dart';
import 'package:firestream/features/chat/screens/groupChatScreen.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  _ChatListScreenState createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen>
    with SingleTickerProviderStateMixin {
  String _currentUserEmail = "";
  late TabController _tabController;
  final TextEditingController newGroupNameController = TextEditingController();
  final TextEditingController addMemberController = TextEditingController();
  final TextEditingController addAdminController = TextEditingController();
  String? newGroupPhotoUrl; // To store the new group photo URL
  String? errorMessage;
  String? settingOnlyAdmin;
  String? messagesOnlyAdmin;
  final FirebaseStorage storage = FirebaseStorage.instance;

  @override
  void initState() {
    super.initState();
    _loadCurrentUserEmail();
    _tabController = TabController(length: 2, vsync: this); // Two tabs
  }

  @override
  void dispose() {
    // Dispose controllers when the dialog is closed
    newGroupNameController.dispose();
    addMemberController.dispose();
    addAdminController.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentUserEmail() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      _currentUserEmail = prefs.getString('userEmail') ?? '';
    });
  }

  Future<String?> _getProfilePicture(String email) async {
    DocumentSnapshot userDoc =
        await FirebaseFirestore.instance.collection('users').doc(email).get();

    if (userDoc.exists) {
      return userDoc['profilePic'] ?? '';
    }
    return null;
  }

  Future<Map<String, dynamic>> _getLatestMessage(String chatId) async {
    final messagesRef = FirebaseFirestore.instance
        .collection('chats')
        .doc(chatId)
        .collection('messages');

    final latestMessageQuery =
        messagesRef.orderBy('timestamp', descending: true).limit(1);
    final latestMessageSnapshot = await latestMessageQuery.get();

    if (latestMessageSnapshot.docs.isNotEmpty) {
      final latestMessageDoc = latestMessageSnapshot.docs.first;

      bool hasImages = latestMessageDoc['imageUrls'] != null &&
          (latestMessageDoc['imageUrls'] as List).isNotEmpty;

      return {
        'text': hasImages
            ? '<image>'
            : (latestMessageDoc['text'] ?? 'No messages yet'),
        'timestamp': latestMessageDoc['timestamp'] as Timestamp?,
      };
    }
    return {'text': 'No messages yet', 'timestamp': null};
  }

  Future<Map<String, dynamic>> _getLatestGroupMessage(String chatId) async {
    final messagesRef = FirebaseFirestore.instance
        .collection('groupChats')
        .doc(chatId)
        .collection('messages');

    final latestMessageQuery =
        messagesRef.orderBy('timestamp', descending: true).limit(1);
    final latestMessageSnapshot = await latestMessageQuery.get();

    if (latestMessageSnapshot.docs.isNotEmpty) {
      final latestMessageDoc = latestMessageSnapshot.docs.first;

      bool hasImages = latestMessageDoc['imageUrls'] != null &&
          (latestMessageDoc['imageUrls'] as List).isNotEmpty;

      return {
        'text': hasImages
            ? '<image>'
            : (latestMessageDoc['text'] ?? 'No messages yet'),
        'timestamp': latestMessageDoc['timestamp'] as Timestamp?,
      };
    }
    return {'text': 'No messages yet', 'timestamp': null};
  }

  Future<void> _deleteChat(String chatId) async {
    try {
      final userEmail = _currentUserEmail;
      final chatRef =
          FirebaseFirestore.instance.collection('chats').doc(chatId);

      // Mark the chat as deleted by the current user
      await chatRef.update({
        'deletedBy': FieldValue.arrayUnion([userEmail]),
      });

      // Check if both users have deleted the chat
      final chatDoc = await chatRef.get();
      List<dynamic> deletedBy = chatDoc['deletedBy'] ?? [];

      if (deletedBy.length == 2) {
        // Retrieve messages from the sub-collection
        var messagesSnapshot = await chatRef.collection('messages').get();

        // Loop through each message document
        for (var messageDoc in messagesSnapshot.docs) {
          var messageData = messageDoc.data();

          // Check if 'imageUrls' exists in the message
          if (messageData['imageUrls'] != null &&
              messageData['imageUrls'] is List) {
            List<String> imageUrls =
                List<String>.from(messageData['imageUrls']);

            // Loop through each image URL and delete from Firebase Storage
            for (var imageUrl in imageUrls) {
              try {
                // Use refFromURL to delete the image directly
                await FirebaseStorage.instance.refFromURL(imageUrl).delete();
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                        'Error deleting image: $e'), // Display the error message
                    duration: const Duration(
                        seconds: 3), // Snackbar visibility duration
                    backgroundColor:
                        Colors.red, // Optional: background color for emphasis
                  ),
                );
              }
            }
          }

          // Delete the message document after deleting associated images
          await messageDoc.reference.delete();
        }

        // Finally, delete the chat document after all messages are deleted
        await chatRef.delete();
      }
    } catch (e) {
      print('Error updating chat deletion: $e');
    }
  }

  void _showDeleteConfirmationDialog(String chatId) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Delete Chat'),
          content: const Text(
              'Are you sure you want to delete this chat permanently?'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                await _deleteChat(chatId);
                Navigator.of(context).pop();
              },
              child: const Text('Delete', style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('FireStream'),
        backgroundColor: Colors.blueAccent,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Chats'),
            Tab(text: 'Groups'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildIndividualChatList(), // Individual Chats
          _buildGroupChatList(), // Group Chats
        ],
      ),
      floatingActionButton: Stack(
        children: [
          Positioned(
            bottom: 16.0,
            right: 16.0,
            child: FloatingActionButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const AddNewChatScreen(),
                  ),
                );
              },
              backgroundColor: Colors.blueAccent,
              child: const Icon(Icons.chat),
            ),
          ),
          Positioned(
            bottom: 90.0, // Adjust position to place above the chat icon
            right: 16.0,
            child: FloatingActionButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const AddGroupChatScreen(),
                  ),
                );
              },
              backgroundColor: Colors.blueAccent,
              child: const Icon(Icons.group),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIndividualChatList() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('chats')
          .where('participants', arrayContains: _currentUserEmail)
          .where('chatType', isEqualTo: 'individual')
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        var chatDocs = snapshot.data!.docs.where((chat) {
          // Exclude chats that have been deleted by the current user
          List<dynamic> deletedBy = chat['deletedBy'] ?? [];
          return !deletedBy.contains(_currentUserEmail);
        }).toList();

        if (chatDocs.isEmpty) {
          return const Center(child: Text('No individual chats available'));
        }

        return _buildChatListView(chatDocs);
      },
    );
  }

  Widget _buildChatListView(List<QueryDocumentSnapshot> chatDocs) {
    return ListView.builder(
      itemCount: chatDocs.length,
      itemBuilder: (context, index) {
        var chat = chatDocs[index];
        var participants = chat['participants'];
        var otherParticipant = participants.firstWhere(
          (email) => email != _currentUserEmail,
        );

        return FutureBuilder<Map<String, dynamic>>(
          future: _getLatestMessage(chat.id),
          builder: (context, messageSnapshot) {
            if (!messageSnapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final messageData = messageSnapshot.data!;
            final String messageText = messageData['text'] ?? 'No messages yet';
            final Timestamp? timestamp = messageData['timestamp'];

            return FutureBuilder<String?>(
              future: _getProfilePicture(otherParticipant),
              builder: (context, profileSnapshot) {
                String? profileUrl = profileSnapshot.data;

                return FutureBuilder<bool>(
                  future: _isContactSaved(otherParticipant),
                  builder: (context, savedContactSnapshot) {
                    bool isSavedContact = savedContactSnapshot.data ?? false;

                    return Card(
                      margin: const EdgeInsets.symmetric(
                          vertical: 8.0, horizontal: 16.0),
                      elevation: 5.0,
                      child: InkWell(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ChatScreen(
                                chatId: chat.id,
                                currentUserEmail: _currentUserEmail,
                                otherParticipantEmail: otherParticipant,
                              ),
                            ),
                          );
                        },
                        child: Stack(
                          children: [
                            ListTile(
                              contentPadding: const EdgeInsets.all(12.0),
                              leading: CircleAvatar(
                                backgroundImage:
                                    profileUrl != null && profileUrl.isNotEmpty
                                        ? NetworkImage(profileUrl)
                                        : const NetworkImage(
                                            "https://via.placeholder.com/150"),
                              ),
                              title: Text(
                                otherParticipant,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold),
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                messageText,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: IconButton(
                                icon: const Icon(
                                  Icons.delete,
                                  color: Colors.red,
                                  size: 20,
                                ),
                                onPressed: () {
                                  _showDeleteConfirmationDialog(chat.id);
                                },
                              ),
                            ),
                            if (isSavedContact)
                              const Positioned(
                                top: 8.0,
                                left: 8.0,
                                child: Icon(
                                  Icons.star,
                                  color: Colors.amber,
                                  size: 16.0,
                                ),
                              ),
                            Positioned(
                              bottom: 8.0,
                              right: 16.0,
                              child: Text(
                                _formatTimestamp(timestamp),
                                style: const TextStyle(
                                  fontSize: 12.0,
                                  color: Colors.grey,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  Future<bool> _isContactSaved(String email) async {
    try {
      DocumentSnapshot savedContactsDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUserEmail)
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

  Widget _buildGroupChatList() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('groupChats')
          .where('participants', arrayContains: _currentUserEmail)
          .where('chatType', isEqualTo: 'group') // Adjust for group chats
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        var chatDocs = snapshot.data!.docs;
        if (chatDocs.isEmpty) {
          return const Center(child: Text('No group chats available'));
        }

        return _buildGroupChatListView(chatDocs);
      },
    );
  }

  Widget _buildGroupChatListView(List<QueryDocumentSnapshot> chatDocs) {
    return ListView.builder(
      itemCount: chatDocs.length,
      itemBuilder: (context, index) {
        var chat = chatDocs[index];
        //var groupParticipants = chat['participants'] as List<dynamic>;
        var admins = chat['admins'] as List<dynamic>; // Get the list of admins
        bool settingOnlyAdmin = chat['SettingOnlyAdmin'] ??
            false; // Check the SettingOnlyAdmin field

        // Assuming the group name is stored in the chat document
        String groupName =
            chat['groupName'] ?? 'Group Chat'; // Default name if not set
        String? groupPhotoUrl =
            chat['groupPhotoUrl']; // Get the group's photo URL

        return FutureBuilder<Map<String, dynamic>>(
          future: _getLatestGroupMessage(chat.id),
          builder: (context, messageSnapshot) {
            if (!messageSnapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final messageData = messageSnapshot.data!;
            final String messageText = messageData['text'] ?? 'No messages yet';
            final Timestamp? timestamp = messageData['timestamp'];

            // Determine if the current user is an admin
            bool isAdmin = admins.contains(_currentUserEmail);

            return Card(
              margin:
                  const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
              elevation: 5.0,
              child: ListTile(
                contentPadding: const EdgeInsets.all(12.0),
                leading: CircleAvatar(
                  backgroundImage: groupPhotoUrl != null &&
                          groupPhotoUrl.isNotEmpty
                      ? NetworkImage(groupPhotoUrl)
                      : const NetworkImage("https://via.placeholder.com/150"),
                ),
                title: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        groupName,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      _formatTimestamp(timestamp),
                      style:
                          const TextStyle(fontSize: 12.0, color: Colors.grey),
                    ),
                  ],
                ),
                subtitle: Text(
                  messageText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Show settings icon based on conditions
                    if (!settingOnlyAdmin ||
                        isAdmin) // Show to admin if SettingOnlyAdmin is true, otherwise show to everyone
                      IconButton(
                        icon: const Icon(
                          Icons.settings,
                          color: Colors.grey,
                        ),
                        onPressed: () {
                          // Navigate to the ChatSettingsScreen
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  ChatSettingsScreen(chatId: chat.id),
                            ),
                          );
                        },
                      ),

                    IconButton(
                      icon: const Icon(
                        Icons.chevron_right,
                        color: Colors.grey,
                      ),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => GroupChatScreen(
                              chatId: chat.id,
                              currentUserEmail: _currentUserEmail,
                              groupName: groupName, // Pass groupName here
                              groupPhotoUrl:
                                  groupPhotoUrl, // Pass groupPhotoUrl here,
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  String _formatTimestamp(Timestamp? timestamp) {
    if (timestamp == null) {
      return '';
    }

    DateTime dateTime = timestamp.toDate();
    return "${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}"; // Format the timestamp as you like
  }
}
