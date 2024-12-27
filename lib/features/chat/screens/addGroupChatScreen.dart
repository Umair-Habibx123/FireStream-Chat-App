import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';

class AddGroupChatScreen extends StatefulWidget {
  const AddGroupChatScreen({super.key});

  @override
  _AddGroupChatScreenState createState() => _AddGroupChatScreenState();
}

class _AddGroupChatScreenState extends State<AddGroupChatScreen> {
  final TextEditingController _groupNameController = TextEditingController();
  String _currentUserEmail = "";
  File? _groupPhoto;
  final ImagePicker _picker = ImagePicker();
  bool _isLoading = false; // Loading state variable

  @override
  void initState() {
    super.initState();
    _loadCurrentUserEmail();
  }

  @override
  void dispose() {
    _groupNameController.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentUserEmail() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      _currentUserEmail = prefs.getString('userEmail') ?? '';
    });
  }

  Future<void> _pickGroupPhoto() async {
    final pickedFile = await _picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() {
        _groupPhoto = File(pickedFile.path);
      });
    }
  }

  Future<void> _createGroupChat() async {
    String groupName = _groupNameController.text.trim();
    if (groupName.isEmpty) {
      setState(() {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Group name is mandatory')),
        );
      });
      return;
    }

    setState(() {
      _isLoading = true; // Set loading to true
    });

    try {
      // Create the group chat
      DocumentReference chatRef =
          await FirebaseFirestore.instance.collection('groupChats').add({
        'groupName': groupName,
        'isGroup': true,
        'chatType': 'group',
        'SettingOnlyAdmin': true,
        'MessagesOnlyAdmin': false,
        'AddMembersBy' : 'anyone',
        'groupPhotoUrl': '', // Placeholder for photo URL
        'participants': [_currentUserEmail],
        'createdBy': _currentUserEmail,
        'admins': [_currentUserEmail],
        'createdDate': FieldValue.serverTimestamp(),
      });

      // If a group photo is selected, upload it and update the chat with the photo URL
      if (_groupPhoto != null) {
        String photoUrl = await _uploadGroupPhoto(chatRef.id);
        await chatRef.update({'groupPhotoUrl': photoUrl});
      }

      Navigator.of(context).pop();
    } catch (e) {
      // Handle errors here
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error creating group: $e')),
      );
    } finally {
      setState(() {
        _isLoading = false; // Set loading to false
      });
    }
  }

  Future<String> _uploadGroupPhoto(String chatId) async {
    // Create a unique file name for the image
    String fileName =
        'group_profile_pictures/$chatId/${DateTime.now().millisecondsSinceEpoch}.png';

    // Upload the image to Firebase Storage
    try {
      await FirebaseStorage.instance.ref(fileName).putFile(_groupPhoto!);

      // Get the download URL
      String downloadUrl =
          await FirebaseStorage.instance.ref(fileName).getDownloadURL();
      return downloadUrl; // Return the download URL
    } catch (e) {
      print("Error uploading photo: $e");
      return ''; // Return an empty string if upload fails
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Group Chat'),
        backgroundColor: Colors.blueAccent,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: _isLoading // Check if loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Group name input
                  Card(
                    elevation: 5,
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: TextField(
                        controller: _groupNameController,
                        decoration: const InputDecoration(
                          labelText: "Enter Group Name",
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Group photo picker
                  InkWell(
                    onTap: _pickGroupPhoto,
                    child: _groupPhoto != null
                        ? CircleAvatar(
                            radius: 50,
                            backgroundImage: FileImage(_groupPhoto!),
                          )
                        : const CircleAvatar(
                            radius: 50,
                            backgroundColor: Colors.grey,
                            child: Icon(Icons.camera_alt, color: Colors.white),
                          ),
                  ),
                  const SizedBox(height: 20),

                  // Create Group button
                  ElevatedButton(
                    onPressed: _createGroupChat,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16.0),
                      backgroundColor: Colors.blueAccent,
                    ),
                    child: const Text("Create Group"),
                  ),
                ],
              ),
      ),
    );
  }
}
