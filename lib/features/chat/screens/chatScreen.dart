import 'package:firestream/features/chat/screens/ContactDetailPage.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:io';
import 'package:photo_view/photo_view.dart';
import 'package:file_picker/file_picker.dart';
import 'package:dio/dio.dart';

class ChatScreen extends StatefulWidget {
  final String chatId;
  final String currentUserEmail;
  final String otherParticipantEmail;

  const ChatScreen({
    super.key,
    required this.chatId,
    required this.currentUserEmail,
    required this.otherParticipantEmail,
  });

  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  final List<File> _selectedImages = [];
  late Future<String?> _profileUrlFuture;
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    // Fetch the other participant's profile picture URL when the screen loads
    _profileUrlFuture = _getProfilePicture(widget.otherParticipantEmail);
  }

  void _openUserDetailPage(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => UserDetailPage(
            email: widget.otherParticipantEmail,
            currentUserEmail: widget.currentUserEmail),
      ),
    );
  }

  void _showTextOptions(BuildContext context, String text, String messageId) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text("Copy"),
              onTap: () {
                Clipboard.setData(ClipboardData(text: text));
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Text copied to clipboard.")),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.forward),
              title: const Text("Forward"),
              onTap: () {
                Navigator.pop(context);
                _forwardMessage(text, isImage: false);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete),
              title: const Text("Delete"),
              onTap: () async {
                Navigator.pop(context);
                _showDeleteConfirmation(messageId);
              },
            ),
          ],
        );
      },
    );
  }

  void _showImageOptions(
      BuildContext context, List<dynamic> imageUrls, String messageId) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.forward),
              title: const Text("Forward"),
              onTap: () {
                Navigator.pop(context);
                _forwardMessage(imageUrls, isImage: true);
              },
            ),
            ListTile(
              leading: const Icon(Icons.download),
              title: const Text("Save"),
              onTap: () async {
                Navigator.pop(context);
                for (var imageUrl in imageUrls) {
                  await _saveImage(imageUrl);
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete),
              title: const Text("Delete"),
              onTap: () async {
                Navigator.pop(context);
                _showDeleteConfirmation(messageId);
              },
            ),
          ],
        );
      },
    );
  }

  void _forwardMessage(dynamic content, {required bool isImage}) {
    // Implement your forwarding logic here
    print(
        isImage ? "Forwarding images: $content" : "Forwarding text: $content");
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
          .collection('chats')
          .doc(widget.chatId)
          .collection('messages')
          .add({
        'text': _messageController.text.trim(),
        'sender': widget.currentUserEmail,
        'timestamp': FieldValue.serverTimestamp(),
        'imageUrls': uploadedImageUrls, // Use the list of uploaded image URLs
      });

      final chatRef =
          FirebaseFirestore.instance.collection('chats').doc(widget.chatId);
      // Retrieve the current chat document
      final chatDoc = await chatRef.get();

      // Check if the 'deletedBy' field exists and if it contains the otherParticipantEmail
      if (chatDoc.exists && chatDoc.data()?['deletedBy'] != null) {
        List<dynamic> deletedByArray =
            chatDoc.data()?['deletedBy'] as List<dynamic>;
        // If otherParticipantEmail exists in the array, remove it
        if (deletedByArray.contains(widget.otherParticipantEmail)) {
          await chatRef.update({
            'deletedBy': FieldValue.arrayRemove([widget.otherParticipantEmail]),
          });
        }
      }

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

  // Function to get profile picture URL from Firestore or SharedPreferences
  Future<String?> _getProfilePicture(String email) async {
    try {
      DocumentSnapshot userDoc =
          await FirebaseFirestore.instance.collection('users').doc(email).get();
      return userDoc['profilePic'];
    } catch (e) {
      return null;
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

  void _deleteMessage(String messageId) async {
    try {
      // Get the message document
      DocumentSnapshot messageSnapshot = await FirebaseFirestore.instance
          .collection('chats')
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
            .collection('chats')
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
        title: FutureBuilder<String?>(
          future: _profileUrlFuture,
          builder: (context, snapshot) {
            String? profileUrl = snapshot.data;

            return Row(
              children: [
                GestureDetector(
                  onTap: () => _openUserDetailPage(context),
                  child: CircleAvatar(
                    backgroundImage: profileUrl != null
                        ? NetworkImage(profileUrl)
                        : const NetworkImage("https://via.placeholder.com/150"),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: GestureDetector(
                    onTap: () => _openUserDetailPage(context),
                    child: Text(
                      widget.otherParticipantEmail,
                      style: const TextStyle(fontSize: 18.0),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
        backgroundColor: Colors.blueAccent,
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('chats')
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
                      onLongPress: () {
                        if (message['text'] != null &&
                            message['text'].isNotEmpty) {
                          _showTextOptions(
                              context, message['text'], message.id);
                        } else if (message['imageUrls'] != null) {
                          _showImageOptions(
                              context, message['imageUrls'], message.id);
                        }
                      },
                      child: Align(
                        alignment: isSentByCurrentUser
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
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
                                        margin: const EdgeInsets.symmetric(
                                            vertical: 4.0, horizontal: 4.0),
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
                                              child: CircularProgressIndicator(
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
                                Container(
                                  margin:
                                      const EdgeInsets.symmetric(vertical: 4.0),
                                  padding: const EdgeInsets.all(10.0),
                                  decoration: BoxDecoration(
                                    color: isSentByCurrentUser
                                        ? Colors.blueAccent
                                        : Colors.grey[300],
                                    borderRadius: BorderRadius.circular(10.0),
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
                              Text(
                                _formatTimestamp(message['timestamp']),
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 12.0,
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
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.photo),
                      onPressed: _pickImages,
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
                        onSubmitted: (value) => _sendMessage(),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.send),
                      onPressed: !_isUploading ? _sendMessage : null,
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
      ),
    );
  }
}
