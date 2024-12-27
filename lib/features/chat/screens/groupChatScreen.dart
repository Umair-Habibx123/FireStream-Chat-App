import 'package:firestream/features/chat/screens/GroupDetailPage.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:io';
import 'package:photo_view/photo_view.dart';
import 'package:file_picker/file_picker.dart';
import 'package:dio/dio.dart';

class GroupChatScreen extends StatefulWidget {
  final String chatId;
  final String currentUserEmail;
  final String groupName;
  final String? groupPhotoUrl;

  const GroupChatScreen({
    super.key,
    required this.chatId,
    required this.currentUserEmail,
    required this.groupName,
    required this.groupPhotoUrl,
  });

  @override
  _GroupChatScreenState createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  final List<File> _selectedImages = [];
// List to hold the URLs of the uploaded images
  bool _isUploading = false;
  bool _canSendMessages = true; // Track if the user can send messages
  bool _messagesOnlyAdmin = false; // Track the MessagesOnlyAdmin setting

  @override
  void initState() {
    super.initState();
    _fetchAdminSettings();
  }

  Future<void> _fetchAdminSettings() async {
    try {
      DocumentSnapshot chatSettingsDoc = await FirebaseFirestore.instance
          .collection('groupChats')
          .doc(widget.chatId)
          .get();

      // Assuming you have a field called 'MessagesOnlyAdmin' in the document
      _messagesOnlyAdmin = chatSettingsDoc['MessagesOnlyAdmin'] ?? false;

      if (_messagesOnlyAdmin) {
        List<String> adminEmails =
            List<String>.from(chatSettingsDoc['admins'] ?? []);
        // Check if the current user's email is in the admin emails
        _canSendMessages = adminEmails.contains(widget.currentUserEmail);
      }

      setState(() {}); // Update the UI based on the fetched data
    } catch (e) {
      print('Failed to fetch admin settings: $e');
    }
  }

  void _showMessageOptions(
      {required bool isSentByCurrentUser,
      required bool isImageMessage,
      required String messageId,
      String? messageText,
      String? imageUrl}) {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return Wrap(
          children: [
            if (isImageMessage && imageUrl != null) ...[
              ListTile(
                leading: const Icon(Icons.save_alt),
                title: const Text('Save'),
                onTap: () {
                  Navigator.of(context).pop();
                  _saveImage(imageUrl);
                },
              ),
              ListTile(
                leading: const Icon(Icons.forward),
                title: const Text('Forward'),
                onTap: () {
                  Navigator.of(context).pop();
                  _forwardMessage(imageUrl, isImage: true);
                },
              ),
              if (isSentByCurrentUser)
                ListTile(
                  leading: const Icon(Icons.delete),
                  title: const Text('Delete'),
                  onTap: () {
                    Navigator.of(context).pop();
                    _showDeleteConfirmation(messageId);
                  },
                ),
            ] else if (!isImageMessage && messageText != null) ...[
              ListTile(
                leading: const Icon(Icons.copy),
                title: const Text('Copy'),
                onTap: () {
                  Navigator.of(context).pop();
                  _copyToClipboard(messageText);
                },
              ),
              ListTile(
                leading: const Icon(Icons.forward),
                title: const Text('Forward'),
                onTap: () {
                  Navigator.of(context).pop();
                  _forwardMessage(messageText, isImage: false);
                },
              ),
              if (isSentByCurrentUser)
                ListTile(
                  leading: const Icon(Icons.delete),
                  title: const Text('Delete'),
                  onTap: () {
                    Navigator.of(context).pop();
                    _showDeleteConfirmation(messageId);
                  },
                ),
            ],
          ],
        );
      },
    );
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Text copied to clipboard')),
    );
  }

  void _forwardMessage(String content, {required bool isImage}) {
    // Add your forwarding logic here
    print(isImage ? 'Forwarding image: $content' : 'Forwarding text: $content');
  }

  Future<void> _saveImage(String imageUrl) async {
    try {
      // Step 1: Let the user select a folder
      String? selectedDirectory = await FilePicker.platform.getDirectoryPath();

      if (selectedDirectory == null) {
        // User canceled the picker
        print("Folder selection canceled.");
        return;
      }

      print("Selected folder: $selectedDirectory");

      // Step 2: Download the image
      Dio dio = Dio();
      String fileName =
          imageUrl.split('/').last.split('?').first; // Extract file name
      String savePath = '$selectedDirectory/$fileName';

      print("Saving image to: $savePath");

      // Download and save the image
      await dio.download(imageUrl, savePath);

      print("Image saved successfully to $savePath");
    } catch (e) {
      print("Error saving image: $e");
    }
  }

  void _sendMessage() async {
    if (_messageController.text.trim().isEmpty && _selectedImages.isEmpty) {
      return;
    }

    setState(() {
      _isUploading = true;
    });

    try {
      // Prepare a list to hold the URLs of uploaded images
      List<String> uploadedImageUrls = [];

      // Upload all selected images and collect their URLs
      for (File imageFile in _selectedImages) {
        String? imageUrl = await _uploadImage(imageFile);
        if (imageUrl != null) {
          uploadedImageUrls.add(imageUrl);
        }
      }

      // Send the message with text and image URLs
      await FirebaseFirestore.instance
          .collection('groupChats')
          .doc(widget.chatId)
          .collection('messages')
          .add({
        'text': _messageController.text.trim(),
        'sender': widget.currentUserEmail,
        'timestamp': FieldValue.serverTimestamp(),
        'imageUrls': uploadedImageUrls, // Use the list of uploaded image URLs
      });

      // Clear the input and selected images after sending the message
      _messageController.clear();
      _selectedImages.clear();
    } catch (e) {
      print('Failed to send message: $e');
    } finally {
      setState(() {
        _isUploading = false;
      });
    }
  }

  Future<void> _pickImages() async {
    try {
      // Use the non-nullable type here
      final List<XFile> pickedFiles = await _picker.pickMultiImage();

      for (XFile pickedFile in pickedFiles) {
        File imageFile = File(pickedFile.path);
        _selectedImages.add(imageFile);
      }

      setState(() {});
    } catch (e) {
      print('Failed to pick images: $e');
    }
  }

  Future<String?> _uploadImage(File imageFile) async {
    // Change return type to String?
    setState(() {
      _isUploading = true;
    });

    try {
      String fileName = DateTime.now().millisecondsSinceEpoch.toString();
      TaskSnapshot uploadTask = await FirebaseStorage.instance
          .ref('chat_images/$fileName')
          .putFile(imageFile);
      String imageUrl = await uploadTask.ref.getDownloadURL();
      return imageUrl; // Return the uploaded image URL
    } catch (e) {
      print('Failed to upload image: $e');
      return null; // Return null in case of failure
    } finally {
      setState(() {
        _isUploading = false;
      });
    }
  }

  void _removeImage(int index) {
    setState(() {
      // Remove the image from the list
      _selectedImages.removeAt(index);
    });
  }

  void _viewImage(String imageUrl) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ImagePreviewScreen(imageUrl: imageUrl),
      ),
    );
  }
  // }

  void _deleteMessage(String messageId) async {
    try {
      // Get the message document
      DocumentSnapshot messageSnapshot = await FirebaseFirestore.instance
          .collection('groupChats')
          .doc(widget.chatId)
          .collection('messages')
          .doc(messageId)
          .get();

      if (messageSnapshot.exists) {
        // Retrieve the imageUrls array
        List<dynamic> imageUrls = messageSnapshot['imageUrls'] ?? [];

        // Check if imageUrls contains URLs before attempting to delete
        if (imageUrls.isNotEmpty) {
          // Delete images from Firebase Storage
          for (String imageUrl in imageUrls) {
            // Extract the path to the image from the URL
            String path = imageUrl.split('?')[0]; // Remove the query parameters
            String imagePath = Uri.decodeFull(path); // Decode the path

            // Delete the image from Storage
            await FirebaseStorage.instance.refFromURL(imagePath).delete();
          }
        }

        // Delete the message document from Firestore
        await FirebaseFirestore.instance
            .collection('groupChats')
            .doc(widget.chatId)
            .collection('messages')
            .doc(messageId)
            .delete();
      }
    } catch (e) {
      print('Error deleting message: $e');
    }
  }

  void _showDeleteConfirmation(String messageId) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete Message'),
          content: const Text('Are you sure you want to delete this message?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                _deleteMessage(messageId);
                Navigator.of(context).pop();
              },
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }

  void _showUserInfo(String email) async {
    // Fetch user info (e.g., username and profile picture) from Firestore
    DocumentSnapshot userDoc =
        await FirebaseFirestore.instance.collection('users').doc(email).get();
    String username = userDoc['username'];
    String profilePicUrl = userDoc['profilePic'];

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(username),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                backgroundImage: NetworkImage(profilePicUrl),
                radius: 30,
              ),
              const SizedBox(height: 10),
              Text('Email: $email'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  String _formatTimestamp(Timestamp? timestamp) {
    if (timestamp == null) return 'Now';

    DateTime dateTime = timestamp.toDate();
    DateTime now = DateTime.now();

    if (dateTime.year == now.year &&
        dateTime.month == now.month &&
        dateTime.day == now.day) {
      return "${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}";
    } else {
      return "${_formatDate(dateTime)}, ${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}";
    }
  }

  String _formatDate(DateTime dateTime) {
    return "${_monthNames[dateTime.month - 1]} ${dateTime.day}, ${dateTime.year}";
  }

  final List<String> _monthNames = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec'
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            CircleAvatar(
              backgroundImage: NetworkImage(widget.groupPhotoUrl ?? ''),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                widget.groupName,
                style: const TextStyle(fontSize: 18.0),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        backgroundColor: Colors.blueAccent,
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () {
              // Navigate to the group details page
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => GroupDetailsPage(
                    groupName: widget.groupName,
                    groupPhotoUrl: widget.groupPhotoUrl,
                    chatId: widget.chatId,
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('groupChats')
                  .doc(widget.chatId)
                  .collection('messages')
                  .orderBy('timestamp', descending: true)
                  .snapshots(),
              builder: (context, AsyncSnapshot<QuerySnapshot> snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                var messages = snapshot.data!.docs;
                return ListView.builder(
                  reverse: true,
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    var message = messages[index];
                    bool isSentByCurrentUser =
                        message['sender'] == widget.currentUserEmail;

                    return GestureDetector(
                      // onLongPress: () {
                      //   if (!isSentByCurrentUser) {
                      //     _showUserInfo(message['sender']);
                      //   } else {
                      //     _showDeleteConfirmation(message.id);
                      //   }
                      // },

                      onLongPress: () {
                        bool isImageMessage = message['imageUrls'] != null &&
                            (message['imageUrls'] as List).isNotEmpty;
                        String? imageUrl =
                            isImageMessage ? message['imageUrls'][0] : null;
                        String? messageText = message['text'];
                        _showMessageOptions(
                          isSentByCurrentUser: isSentByCurrentUser,
                          isImageMessage: isImageMessage,
                          messageId: message.id,
                          messageText: messageText,
                          imageUrl: imageUrl,
                        );
                      },

                      child: Align(
                        alignment: isSentByCurrentUser
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (!isSentByCurrentUser)
                                FutureBuilder<DocumentSnapshot>(
                                  future: FirebaseFirestore.instance
                                      .collection('users')
                                      .doc(message['sender'])
                                      .get(),
                                  builder: (context, snapshot) {
                                    if (snapshot.connectionState ==
                                        ConnectionState.waiting) {
                                      return const CircularProgressIndicator();
                                    }
                                    if (snapshot.hasError ||
                                        !snapshot.hasData) {
                                      return const CircleAvatar(
                                        backgroundColor: Colors.grey,
                                        radius: 20,
                                      );
                                    }
                                    var userData = snapshot.data!;
                                    String profilePicUrl =
                                        userData['profilePic'] ?? '';

                                    return CircleAvatar(
                                      backgroundImage:
                                          NetworkImage(profilePicUrl),
                                      radius: 20,
                                    );
                                  },
                                ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: isSentByCurrentUser
                                      ? CrossAxisAlignment.end
                                      : CrossAxisAlignment.start,
                                  children: [
                                    if (message['imageUrls'] != null)
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: List.generate(
                                          (message['imageUrls'] as List).length,
                                          (index) => GestureDetector(
                                            onTap: () => _viewImage(
                                                message['imageUrls'][index]),
                                            child: Container(
                                              margin:
                                                  const EdgeInsets.symmetric(
                                                      vertical: 4.0,
                                                      horizontal: 4.0),
                                              child: Image.network(
                                                message['imageUrls'][index],
                                                width: 100,
                                                height: 100,
                                                fit: BoxFit.cover,
                                                loadingBuilder: (context, child,
                                                    loadingProgress) {
                                                  if (loadingProgress == null) {
                                                    return child;
                                                  }
                                                  return Center(
                                                    child:
                                                        CircularProgressIndicator(
                                                      value: loadingProgress
                                                                  .expectedTotalBytes !=
                                                              null
                                                          ? loadingProgress
                                                                  .cumulativeBytesLoaded /
                                                              (loadingProgress
                                                                      .expectedTotalBytes ??
                                                                  1)
                                                          : null,
                                                    ),
                                                  );
                                                },
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    if (message['text'] != null &&
                                        message['text'].isNotEmpty)
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(10.0),
                                            decoration: BoxDecoration(
                                              color: isSentByCurrentUser
                                                  ? Colors.blue
                                                  : Colors.grey[300],
                                              borderRadius:
                                                  BorderRadius.circular(15),
                                            ),
                                            child: Text(
                                              message['text'],
                                              style: TextStyle(
                                                color: isSentByCurrentUser
                                                    ? Colors.white
                                                    : Colors.black,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    const SizedBox(height: 5),
                                    Text(
                                      _formatTimestamp(message['timestamp']),
                                      style: TextStyle(
                                        fontSize: 12.0,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),

          // Selected images horizontal scroll view
          if (_selectedImages.isNotEmpty)
            SizedBox(
              height: 100,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _selectedImages.length,
                itemBuilder: (context, index) {
                  return Stack(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4.0),
                        child: Image.file(
                          _selectedImages[index],
                          width: 100,
                          height: 100,
                          fit: BoxFit.cover,
                        ),
                      ),
                      Positioned(
                        right: 0,
                        child: IconButton(
                          icon: const Icon(Icons.remove_circle,
                              color: Colors.red),
                          onPressed: () => _removeImage(index),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),

          if (_isUploading) const LinearProgressIndicator(),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              children: [
                if (!_canSendMessages)
                  const Text(
                    'You cannot send messages. Admins only.',
                    style: TextStyle(color: Colors.red),
                  ),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.photo),
                      onPressed: _canSendMessages ? _pickImages : null,
                    ),
                    Expanded(
                      child: TextField(
                        controller: _messageController,
                        decoration: InputDecoration(
                          hintText: 'Send a message...',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(30),
                            borderSide: BorderSide.none,
                          ),
                          filled: true,
                          fillColor: Colors.grey[200],
                        ),
                        onSubmitted: (value) =>
                            _canSendMessages ? _sendMessage() : null,
                        enabled: _canSendMessages,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.send),
                      onPressed: _canSendMessages && !_isUploading
                          ? _sendMessage
                          : null,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ImagePreviewScreen extends StatelessWidget {
  final String imageUrl;

  const ImagePreviewScreen({super.key, required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PhotoView(
        imageProvider: NetworkImage(imageUrl),
        heroAttributes: const PhotoViewHeroAttributes(tag: 'imageHero'),
      ),
    );
  }
}
