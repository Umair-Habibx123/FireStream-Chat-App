import 'package:firestream/features/chat/screens/GroupAdminScreen.dart';
import 'package:firestream/features/chat/screens/GroupParticipantsScreen.dart';
import 'package:flutter/material.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';

class ChatSettingsScreen extends StatefulWidget {
  final String chatId;

  const ChatSettingsScreen({super.key, required this.chatId});

  @override
  _ChatSettingsScreenState createState() => _ChatSettingsScreenState();
}

class _ChatSettingsScreenState extends State<ChatSettingsScreen> {
  final TextEditingController newGroupNameController = TextEditingController();
  String? newGroupPhotoUrl;
  bool isLoading = false;
  String? errorMessage;
  bool isPhotoLoading = true; // Track photo loading status

  @override
  void initState() {
    super.initState();
    _loadCurrentGroupData(widget.chatId);
  }

  Future<void> _loadCurrentGroupData(String chatId) async {
    setState(() => isLoading = true);

    try {
      DocumentSnapshot groupChatDoc = await FirebaseFirestore.instance
          .collection('groupChats')
          .doc(chatId)
          .get();
      if (groupChatDoc.exists) {
        setState(() {
          newGroupNameController.text = groupChatDoc['groupName'] ?? '';
          newGroupPhotoUrl = groupChatDoc['groupPhotoUrl'];
        });
      }
    } catch (e) {
      setState(() {
        errorMessage = "Failed to load group data: ${e.toString()}";
      });
    } finally {
      setState(() {
        isLoading = false;
        isPhotoLoading = false; // Stop showing the loader once data is fetched
      });
    }
  }

  Future<void> _pickGroupPhoto() async {
    // Pick the image from the gallery
    final pickedFile =
        await ImagePicker().pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() {
        // Show the picked image immediately
        newGroupPhotoUrl = pickedFile.path;
      });

      // Upload the new image and update Firestore
      String? uploadedUrl = await _uploadGroupPhoto(pickedFile.path);

      if (uploadedUrl != null) {
        // Update the group photo URL in Firestore
        await FirebaseFirestore.instance
            .collection('groupChats')
            .doc(widget.chatId)
            .update({'groupPhotoUrl': uploadedUrl});

        // Update the state with the new URL from Firebase Storage
        setState(() {
          newGroupPhotoUrl = uploadedUrl;
        });
      }
    }
  }

  Future<String?> _uploadGroupPhoto(String filePath) async {
    try {
      // Get the current group data to retrieve the existing photo URL
      DocumentSnapshot groupChatDoc = await FirebaseFirestore.instance
          .collection('groupChats')
          .doc(widget.chatId)
          .get();

      if (groupChatDoc.exists && groupChatDoc['groupPhotoUrl'] != null) {
        String existingPhotoUrl = groupChatDoc['groupPhotoUrl'];

        // Delete the existing group photo if it exists
        await _deleteExistingPhoto(existingPhotoUrl);
      }

      // Now proceed to upload the new photo
      final storageRef = FirebaseStorage.instance.ref();
      String fileName =
          'group_profile_pictures/${widget.chatId}/${DateTime.now().millisecondsSinceEpoch}.jpg';
      final photoRef = storageRef.child(fileName);

      await photoRef.putFile(File(filePath));
      return await photoRef.getDownloadURL();
    } catch (e) {
      setState(() {
        errorMessage = "Failed to upload photo: ${e.toString()}";
      });
      return null;
    }
  }

// Helper method to delete the existing photo
  Future<void> _deleteExistingPhoto(String photoUrl) async {
    // Check if the photoUrl is empty or null
    if (photoUrl.isEmpty) {
      return; // Do nothing if photoUrl is empty
    }

    try {
      final ref = FirebaseStorage.instance.refFromURL(photoUrl);
      await ref.delete();
    } catch (e) {
      setState(() {
        errorMessage = "Failed to delete the existing photo: ${e.toString()}";
      });
    }
  }

  // Function to show the add participant dialog
  Future<void> _showAddParticipantDialog(BuildContext context) async {
    TextEditingController emailController = TextEditingController();
    String? errorMessage; // To store error messages
    bool isChecking = false; // To show a loader during the email check

    // Show the dialog
    return showDialog<void>(
      context: context,
      barrierDismissible: false, // Prevent dismissal by tapping outside
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            return AlertDialog(
              title: const Text('Add Member/Participant'),
              content: SingleChildScrollView(
                child: ListBody(
                  children: <Widget>[
                    TextField(
                      controller: emailController,
                      decoration: const InputDecoration(
                        labelText: 'Enter email',
                      ),
                    ),
                    if (isChecking)
                      const Padding(
                        padding: EdgeInsets.only(top: 10),
                        child:
                            CircularProgressIndicator(), // Loader while checking email
                      ),
                    if (errorMessage != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(
                          errorMessage!,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                  ],
                ),
              ),
              actions: <Widget>[
                TextButton(
                  child: const Text('Cancel'),
                  onPressed: () {
                    Navigator.of(context).pop(); // Close the dialog on cancel
                  },
                ),
                TextButton(
                  child: const Text('Save'),
                  onPressed: () async {
                    String email = emailController.text.trim();

                    if (email.isNotEmpty) {
                      setState(
                          () => isChecking = true); // Show loading indicator
                      try {
                        // Check if the email exists in the 'users' collection
                        // Check if the email document exists in the 'users' collection
                        DocumentSnapshot userDoc = await FirebaseFirestore
                            .instance
                            .collection('users')
                            .doc(email)
                            .get();

                        if (userDoc.exists) {
                          // If email exists, add to participants
                          DocumentReference chatDoc = FirebaseFirestore.instance
                              .collection('groupChats')
                              .doc(widget.chatId);

                          await chatDoc.update({
                            'participants': FieldValue.arrayUnion([email]),
                          });

                          Navigator.of(context)
                              .pop(); // Close dialog after saving
                        } else {
                          // Email does not exist in the 'users' collection
                          setState(() {
                            errorMessage = "This email is not registered.";
                          });
                        }
                      } catch (e) {
                        setState(() {
                          errorMessage =
                              "Failed to add participant: ${e.toString()}";
                        });
                      } finally {
                        setState(
                            () => isChecking = false); // Hide loading indicator
                      }
                    }
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showMessagesSettingsDialog(BuildContext context) async {
    bool? selectedValue;
    bool isLoading = true;
    String? errorMessage;

    // First, load the current value of 'SettingOnlyAdmin' from Firestore
    try {
      DocumentSnapshot groupChatDoc = await FirebaseFirestore.instance
          .collection('groupChats')
          .doc(widget.chatId)
          .get();

      if (groupChatDoc.exists) {
        bool settingOnlyAdmin = groupChatDoc['MessagesOnlyAdmin'] ?? false;
        selectedValue =
            settingOnlyAdmin; // Set the current value of the dropdown
      }
    } catch (e) {
      errorMessage = "Failed to load Messages settings: ${e.toString()}";
    } finally {
      isLoading = false;
    }

    // Show the dialog
    return showDialog<void>(
      context: context,
      barrierDismissible: false, // Prevent dismissal by tapping outside
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            return AlertDialog(
              title: const Text('Messages Settings'),
              content: isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text("Allow Messages only send by Admin"),
                        DropdownButton<bool>(
                          value: selectedValue,
                          items: const [
                            DropdownMenuItem(
                              value: true,
                              child: Text('True'),
                            ),
                            DropdownMenuItem(
                              value: false,
                              child: Text('False'),
                            ),
                          ],
                          onChanged: (bool? newValue) {
                            setState(() {
                              selectedValue = newValue;
                            });
                          },
                        ),
                        if (errorMessage != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Text(
                              errorMessage!,
                              style: const TextStyle(color: Colors.red),
                            ),
                          ),
                      ],
                    ),
              actions: <Widget>[
                TextButton(
                  child: const Text('Cancel'),
                  onPressed: () {
                    Navigator.of(context).pop(); // Close the dialog
                  },
                ),
                TextButton(
                  child: const Text('Save'),
                  onPressed: () async {
                    if (selectedValue != null) {
                      try {
                        // Update the 'SettingOnlyAdmin' field in Firestore
                        await FirebaseFirestore.instance
                            .collection('groupChats')
                            .doc(widget.chatId)
                            .update({
                          'MessagesOnlyAdmin': selectedValue,
                        });

                        Navigator.of(context)
                            .pop(); // Close the dialog on success
                      } catch (e) {
                        setState(() {
                          errorMessage =
                              "Failed to update Messages settings: ${e.toString()}";
                        });
                      }
                    }
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showAdminSettingsDialog(BuildContext context) async {
    bool? selectedValue;
    bool isLoading = true;
    String? errorMessage;

    // First, load the current value of 'SettingOnlyAdmin' from Firestore
    try {
      DocumentSnapshot groupChatDoc = await FirebaseFirestore.instance
          .collection('groupChats')
          .doc(widget.chatId)
          .get();

      if (groupChatDoc.exists) {
        bool settingOnlyAdmin = groupChatDoc['SettingOnlyAdmin'] ?? false;
        selectedValue =
            settingOnlyAdmin; // Set the current value of the dropdown
      }
    } catch (e) {
      errorMessage = "Failed to load admin settings: ${e.toString()}";
    } finally {
      isLoading = false;
    }

    // Show the dialog
    return showDialog<void>(
      context: context,
      barrierDismissible: false, // Prevent dismissal by tapping outside
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            return AlertDialog(
              title: const Text('Admin Settings'),
              content: isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text("Allow settings change only by Admin"),
                        DropdownButton<bool>(
                          value: selectedValue,
                          items: const [
                            DropdownMenuItem(
                              value: true,
                              child: Text('True'),
                            ),
                            DropdownMenuItem(
                              value: false,
                              child: Text('False'),
                            ),
                          ],
                          onChanged: (bool? newValue) {
                            setState(() {
                              selectedValue = newValue;
                            });
                          },
                        ),
                        if (errorMessage != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Text(
                              errorMessage!,
                              style: const TextStyle(color: Colors.red),
                            ),
                          ),
                      ],
                    ),
              actions: <Widget>[
                TextButton(
                  child: const Text('Cancel'),
                  onPressed: () {
                    Navigator.of(context).pop(); // Close the dialog
                  },
                ),
                TextButton(
                  child: const Text('Save'),
                  onPressed: () async {
                    if (selectedValue != null) {
                      try {
                        // Update the 'SettingOnlyAdmin' field in Firestore
                        await FirebaseFirestore.instance
                            .collection('groupChats')
                            .doc(widget.chatId)
                            .update({
                          'SettingOnlyAdmin': selectedValue,
                        });

                        Navigator.of(context)
                            .pop(); // Close the dialog on success
                      } catch (e) {
                        setState(() {
                          errorMessage =
                              "Failed to update admin settings: ${e.toString()}";
                        });
                      }
                    }
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  // Function to show the add participant dialog
  Future<void> _showAddAdminDialog(BuildContext context) async {
    TextEditingController emailController = TextEditingController();
    String? errorMessage; // To store error messages
    bool isChecking = false; // To show a loader during the email check

    // Show the dialog
    return showDialog<void>(
      context: context,
      barrierDismissible: false, // Prevent dismissal by tapping outside
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            return AlertDialog(
              title: const Text('Add Admin'),
              content: SingleChildScrollView(
                child: ListBody(
                  children: <Widget>[
                    TextField(
                      controller: emailController,
                      decoration: const InputDecoration(
                        labelText: 'Enter email',
                      ),
                    ),
                    if (isChecking)
                      const Padding(
                        padding: EdgeInsets.only(top: 10),
                        child:
                            CircularProgressIndicator(), // Loader while checking email
                      ),
                    if (errorMessage != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(
                          errorMessage!,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                  ],
                ),
              ),
              actions: <Widget>[
                TextButton(
                  child: const Text('Cancel'),
                  onPressed: () {
                    Navigator.of(context).pop(); // Close the dialog on cancel
                  },
                ),
                TextButton(
                  child: const Text('Save'),
                  onPressed: () async {
                    String email = emailController.text.trim();

                    if (email.isNotEmpty) {
                      setState(
                          () => isChecking = true); // Show loading indicator
                      try {
                        // Check if the email exists in the 'users' collection
                        // Check if the email document exists in the 'users' collection
                        DocumentSnapshot userDoc = await FirebaseFirestore
                            .instance
                            .collection('users')
                            .doc(email)
                            .get();

                        if (userDoc.exists) {
                          // If email exists, add to participants
                          DocumentReference chatDoc = FirebaseFirestore.instance
                              .collection('groupChats')
                              .doc(widget.chatId);

                          await chatDoc.update({
                            'admins': FieldValue.arrayUnion([email]),
                            'participants': FieldValue.arrayUnion([email]),
                          });

                          Navigator.of(context)
                              .pop(); // Close dialog after saving
                        } else {
                          // Email does not exist in the 'users' collection
                          setState(() {
                            errorMessage = "This email is not registered.";
                          });
                        }
                      } catch (e) {
                        setState(() {
                          errorMessage = "Failed to add admin: ${e.toString()}";
                        });
                      } finally {
                        setState(
                            () => isChecking = false); // Hide loading indicator
                      }
                    }
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  // Function to show the change group name dialog
  Future<void> _showChangeGroupNameDialog(BuildContext context) async {
    TextEditingController groupNameController = TextEditingController(
      text: newGroupNameController.text, // Pre-fill the existing group name
    );

    // Show the dialog
    return showDialog<void>(
      context: context,
      barrierDismissible: false, // User must tap a button to dismiss the dialog
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Change Group Name'),
          content: SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                TextField(
                  controller: groupNameController,
                  decoration: const InputDecoration(
                    labelText: 'Group Name',
                  ),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop(); // Close the dialog on cancel
              },
            ),
            TextButton(
              child: const Text('Save'),
              onPressed: () async {
                // Save the new group name
                String newGroupName = groupNameController.text.trim();

                if (newGroupName.isNotEmpty) {
                  setState(() => isLoading = true); // Show loading indicator

                  try {
                    // Update the group name in Firestore
                    await FirebaseFirestore.instance
                        .collection('groupChats')
                        .doc(widget.chatId)
                        .update({
                      'groupName': newGroupName,
                    });

                    setState(() {
                      newGroupNameController.text =
                          newGroupName; // Update the local state
                    });

                    Navigator.of(context)
                        .pop(); // Close the dialog after saving
                  } catch (e) {
                    setState(() {
                      errorMessage =
                          "Failed to update group name: ${e.toString()}";
                    });
                  } finally {
                    setState(() => isLoading = false); // Hide loading indicator
                  }
                }
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _showAddMembersByDialog(BuildContext context) async {
    // Controller to manage dropdown value
    String selectedValue = 'anyone'; // Default value
    bool isLoading = true;
    String errorMessage = '';

    // Fetch existing value from Firestore
    try {
      DocumentSnapshot doc = await FirebaseFirestore.instance
          .collection('groupChats')
          .doc(widget.chatId)
          .get();

      // Cast the data to a Map<String, dynamic>
      final data = doc.data() as Map<String, dynamic>?;

      // Get the current value of 'AddMembersBy'
      selectedValue = data?['AddMembersBy'] ?? 'anyone';
    } catch (e) {
      errorMessage = "Failed to load existing value: ${e.toString()}";
    } finally {
      isLoading = false;
    }

    // Show the dialog
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Who can Add Members'),
          content: isLoading
              ? const Center(child: CircularProgressIndicator())
              : StatefulBuilder(
                  builder: (BuildContext context, StateSetter setState) {
                    return DropdownButton<String>(
                      value: selectedValue,
                      isExpanded: true,
                      items: const [
                        DropdownMenuItem(
                            value: 'anyone', child: Text('Anyone')),
                        DropdownMenuItem(
                            value: 'admin only', child: Text('Admin Only')),
                      ],
                      onChanged: (String? newValue) {
                        if (newValue != null) {
                          setState(() {
                            selectedValue = newValue; // Update dropdown value
                          });
                        }
                      },
                    );
                  },
                ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop(); // Close the dialog on cancel
              },
            ),
            TextButton(
              child: const Text('Save'),
              onPressed: () async {
                // Save the selected value to Firebase
                try {
                  await FirebaseFirestore.instance
                      .collection('groupChats')
                      .doc(widget.chatId)
                      .update({
                    'AddMembersBy': selectedValue,
                  });

                  Navigator.of(context).pop(); // Close the dialog after saving
                } catch (e) {
                  // Handle errors (e.g., show a snackbar)
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text("Failed to update: ${e.toString()}"),
                  ));
                }
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildSettingsOption(String title, IconData icon, Function onTap) {
    return ListTile(
      title: Text(title),
      trailing: const Icon(Icons.arrow_forward_ios),
      leading: Icon(icon),
      onTap: () => onTap(),
    );
  }

  // Function to show the group admin dialog
  void _showGroupAdminDialog(BuildContext context) {
    // Implement dialog to show group admin information
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AdminsScreen(
            chatId: widget.chatId), // Pass chatId to the new screen
      ),
    );
  }

// Function to show the group participants dialog
  void _showGroupParticipantsDialog(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ParticipantsScreen(
            chatId: widget.chatId), // Pass chatId to the new screen
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Chat Settings"),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: 20),

                  // Group Profile Photo with Pencil Icon to Edit
                  GestureDetector(
                    onTap: _pickGroupPhoto,
                    child: Stack(
                      alignment: Alignment.bottomRight,
                      children: [
                        CircleAvatar(
                          radius: 60,
                          backgroundColor: Colors.grey[200],
                          child: newGroupPhotoUrl == null
                              ? const CircularProgressIndicator() // Show loader before image loads
                              : ClipOval(
                                  child: newGroupPhotoUrl!.startsWith(
                                          'http') // Check if it's an online URL
                                      ? FadeInImage.assetNetwork(
                                          placeholder:
                                              'assets/placeholder_image.png',
                                          image: newGroupPhotoUrl!,
                                          fit: BoxFit.cover,
                                          width: 120.0,
                                          height: 120.0,
                                          imageErrorBuilder:
                                              (context, error, stackTrace) {
                                            return const Icon(
                                                Icons.error_outline,
                                                size: 60);
                                          },
                                        )
                                      : Image.file(
                                          File(
                                              newGroupPhotoUrl!), // Show local image until uploaded
                                          fit: BoxFit.cover,
                                          width: 120.0,
                                          height: 120.0,
                                        ),
                                ),
                        ),
                        const CircleAvatar(
                          radius: 20,
                          backgroundColor: Colors.blue,
                          child: Icon(Icons.edit, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Group Name Text
                  Text(
                    newGroupNameController.text,
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 20),

                  // List View with Options
                  _buildSettingsOption(
                    "Change Group Name",
                    Icons.edit,
                    () {
                      _showChangeGroupNameDialog(
                          context); // Show the dialog when clicked
                    },
                  ),

                  _buildSettingsOption(
                    "Add Member by email",
                    Icons.person_add,
                    () {
                      _showAddParticipantDialog(
                          context); // Show the dialog when clicked
                    },
                  ),

                  _buildSettingsOption(
                    "Add Member as Admin",
                    Icons.admin_panel_settings,
                    () {
                      _showAddAdminDialog(context);
                      // Logic to add admin
                    },
                  ),

                  _buildSettingsOption(
                    "Allow Group Settings Only by Admin",
                    Icons.settings,
                    () {
                      _showAdminSettingsDialog(context);
                      // Logic for admin settings
                    },
                  ),

                  _buildSettingsOption(
                    "Allow Group Messages Only send by Admin",
                    Icons.message,
                    () {
                      _showMessagesSettingsDialog(context);
                      // Logic for admin-only messaging
                    },
                  ),

                  // New "Delete Group" Option
                  _buildSettingsOption(
                    "Add Members By",
                    Icons.person_add_alt_1,
                    () {
                      _showAddMembersByDialog(context);
                    },
                  ),

                  _buildSettingsOption(
                    "Show Group Admin", // New option for showing group admin
                    Icons.admin_panel_settings,
                    () {
                      _showGroupAdminDialog(
                          context); // Show the dialog or screen for group admin
                    },
                  ),

                  _buildSettingsOption(
                    "Show Group Participants", // New option for showing group participants
                    Icons.people,
                    () {
                      _showGroupParticipantsDialog(
                          context); // Show the dialog or screen for group participants
                    },
                  ),

                  // New "Delete Group" Option
                  _buildSettingsOption(
                    "Delete Group",
                    Icons.delete_forever,
                    () {
                      _showDeleteGroupConfirmationDialog(
                          context); // Show the delete confirmation dialog
                    },
                  ),

                  // Error message display
                  if (errorMessage != null)
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Text(
                        errorMessage!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                ],
              ),
            ),
    );
  }

// Function to show the delete confirmation dialog
  void _showDeleteGroupConfirmationDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("Delete Group"),
          content: const Text(
              "Are you sure you want to delete this group? All messages will be deleted permanently."),
          actions: [
            TextButton(
              child: const Text("Cancel"),
              onPressed: () {
                Navigator.of(context).pop(); // Close the dialog
              },
            ),
            TextButton(
              child: const Text("Yes, Delete"),
              onPressed: () async {
                // Call the function to delete the group
                await _deleteGroup();
                Navigator.of(context).pop(); // Close the dialog after deletion
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _deleteGroup() async {
    try {
      // Retrieve the chat document to get the group photo URL
      DocumentSnapshot chatDoc = await FirebaseFirestore.instance
          .collection('groupChats')
          .doc(widget.chatId)
          .get();

      final chatRef = FirebaseFirestore.instance
          .collection('groupChats')
          .doc(widget.chatId);

      // Get the group photo URL
      String? groupPhotoUrl = chatDoc['groupPhotoUrl'] as String?;

      // Check if groupPhotoUrl is not null or empty
      if (groupPhotoUrl != null && groupPhotoUrl.isNotEmpty) {
        // Log the URL to ensure it's the correct one
        print("Deleting photo at URL: $groupPhotoUrl");

        // Delete the photo directly using the full URL
        await FirebaseStorage.instance
            .refFromURL(groupPhotoUrl)
            .delete(); // Delete the group photo from storage
      }

      // Retrieve messages from the sub-collection
      var messagesSnapshot = await chatRef.collection('messages').get();

      // Loop through each message document
      for (var messageDoc in messagesSnapshot.docs) {
        var messageData = messageDoc.data();

        // Check if 'imageUrls' exists in the message
        if (messageData['imageUrls'] != null &&
            messageData['imageUrls'] is List) {
          List<String> imageUrls = List<String>.from(messageData['imageUrls']);

          // Loop through each image URL and delete from Firebase Storage
          for (var imageUrl in imageUrls) {
            try {
              // Use refFromURL to delete the image directly
              await FirebaseStorage.instance.refFromURL(imageUrl).delete();
              print("Deleted image at URL: $imageUrl");
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
      }

      // Now delete the chat document from Firestore
      await chatRef.delete();
      print("Chat document deleted: ${widget.chatId}");

      // Clear any existing error messages and navigate back
      setState(() {
        errorMessage = null; // Clear any existing error messages
      });

      Navigator.of(context).pop(); // Navigate back after deleting the group
    } catch (e) {
      setState(() {
        errorMessage = "Failed to delete group: ${e.toString()}";
      });
    }
  }
}
