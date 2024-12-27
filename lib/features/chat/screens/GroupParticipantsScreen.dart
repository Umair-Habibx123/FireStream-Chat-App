import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ParticipantsScreen extends StatefulWidget {
  final String chatId;

  const ParticipantsScreen({super.key, required this.chatId});

  @override
  _ParticipantsScreenState createState() => _ParticipantsScreenState();
}

class _ParticipantsScreenState extends State<ParticipantsScreen> {
  List<String> participants = [];
  List<String> admins = []; // Assuming admins are also stored in Firestore
  bool isLoading = true;
  String? errorMessage;
  String? currentUserEmail;

  @override
  void initState() {
    super.initState();
    _loadCurrentUserEmail();
    _loadParticipants();
  }

  // Load current user's email from shared preferences
  Future<void> _loadCurrentUserEmail() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      currentUserEmail =
          prefs.getString('userEmail'); // Adjust the key if necessary
    });
  }

  // Load participants and admins from Firestore
  Future<void> _loadParticipants() async {
    try {
      DocumentSnapshot chatDoc = await FirebaseFirestore.instance
          .collection('groupChats')
          .doc(widget.chatId)
          .get();
      List<String> participantEmails =
          List<String>.from(chatDoc['participants'] ?? []);
      admins = List<String>.from(chatDoc['admins'] ?? []); // Load admins

      setState(() {
        participants = participantEmails;
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        errorMessage = "Failed to load participants: ${e.toString()}";
        isLoading = false;
      });
    }
  }

  // Function to delete a participant
  Future<void> _deleteParticipant(String email) async {
    try {
      // Check if the participant is an admin
      bool isAdmin = admins.contains(email);

      // Remove the participant from Firestore
      await FirebaseFirestore.instance
          .collection('groupChats')
          .doc(widget.chatId)
          .update({
        'participants': FieldValue.arrayRemove([email]),
      });

      // Update the local participants list
      setState(() {
        participants.remove(email);
        if (isAdmin) {
          admins.remove(email); // Remove from local admins list
        }
      });

      // If the deleted email is an admin, remove them from Firestore admin list
      if (isAdmin) {
        await _removeAdmin(email);
      }

      // Check for remaining admins
      if (!admins.contains(email)) {
        // If no admins left, check for remaining participants
        if (admins.isEmpty) {
          // If no admins left, assign a random user as admin if there are still participants
          if (participants.isNotEmpty) {
            String newAdmin =
                participants[0]; // Assign first participant as new admin
            await _assignNewAdmin(newAdmin);
          } else {
            // If no participants left, delete the group
            await _deleteGroup();
          }
        }
      }
    } catch (e) {
      setState(() {
        errorMessage = "Failed to delete participant: ${e.toString()}";
      });
    }
  }

// Function to remove admin from Firestore
  Future<void> _removeAdmin(String email) async {
    try {
      await FirebaseFirestore.instance
          .collection('groupChats')
          .doc(widget.chatId)
          .update({
        'admins': FieldValue.arrayRemove([email]),
      });
    } catch (e) {
      setState(() {
        errorMessage = "Failed to remove admin: ${e.toString()}";
      });
    }
  }

  // Function to assign a new admin
  Future<void> _assignNewAdmin(String email) async {
    try {
      await FirebaseFirestore.instance
          .collection('groupChats')
          .doc(widget.chatId)
          .update({
        'admins': FieldValue.arrayUnion([email]),
      });
    } catch (e) {
      setState(() {
        errorMessage = "Failed to assign new admin: ${e.toString()}";
      });
    }
  }

  // Function to delete the group
  Future<void> _deleteGroup() async {
    try {
      await FirebaseFirestore.instance
          .collection('groupChats')
          .doc(widget.chatId)
          .delete();
      Navigator.of(context).pop(); // Navigate back after deletion
    } catch (e) {
      setState(() {
        errorMessage = "Failed to delete group: ${e.toString()}";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Group Participants"),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : errorMessage != null
              ? Center(
                  child: Text(errorMessage!,
                      style: const TextStyle(color: Colors.red)))
              : ListView.builder(
                  itemCount: participants.length,
                  itemBuilder: (context, index) {
                    return FutureBuilder<DocumentSnapshot>(
                      future: FirebaseFirestore.instance
                          .collection('users')
                          .doc(participants[index])
                          .get(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const ListTile(
                            title: Text("Loading..."),
                          );
                        }

                        if (!snapshot.hasData || !snapshot.data!.exists) {
                          return const ListTile(
                            title: Text("User not found"),
                          );
                        }

                        var userData = snapshot.data!;
                        var profilePhotoUrl = userData['profilePic'] ??
                            ''; // Assuming this field exists

                        return ListTile(
                          leading: CircleAvatar(
                            backgroundImage: profilePhotoUrl.isNotEmpty
                                ? NetworkImage(profilePhotoUrl)
                                : const AssetImage(
                                    'assets/placeholder_image.png'),
                          ),
                          title: Text(participants[index] +
                              (participants[index] == currentUserEmail
                                  ? " (you)"
                                  : "")),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () {
                              _deleteParticipant(participants[index]);
                            },
                          ),
                        );
                      },
                    );
                  },
                ),
    );
  }
}
