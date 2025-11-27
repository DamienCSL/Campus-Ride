import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class EditProfilePage extends StatefulWidget {
  final Map currentProfile;

  const EditProfilePage({Key? key, required this.currentProfile})
      : super(key: key);

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final supabase = Supabase.instance.client;

  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();

  File? imageFile;
  bool isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl.text = widget.currentProfile['full_name'] ?? "";
    _phoneCtrl.text = widget.currentProfile['phone'] ?? "";
  }

  Future<void> pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);

    if (picked != null) {
      setState(() {
        imageFile = File(picked.path);
      });
    }
  }

  Future<String?> uploadAvatar(String userId) async {
    if (imageFile == null) return null;

    final filePath = "avatars/$userId.jpg";

    await supabase.storage
        .from("avatars")
        .upload(filePath, imageFile!, fileOptions: const FileOptions(upsert: true));

    final publicUrl =
    supabase.storage.from("avatars").getPublicUrl(filePath);

    return publicUrl;
  }

  Future<void> saveProfile() async {
    setState(() => isSaving = true);

    final user = supabase.auth.currentUser;
    if (user == null) return;

    String? avatarUrl = await uploadAvatar(user.id);

    await supabase.from('profiles').update({
      'full_name': _nameCtrl.text.trim(),
      'phone': _phoneCtrl.text.trim(),
      if (avatarUrl != null) 'avatar_url': avatarUrl
    }).eq('id', user.id);

    setState(() => isSaving = false);

    Navigator.pop(context); // return to Profile Page
  }

  @override
  Widget build(BuildContext context) {
    final avatar = widget.currentProfile['avatar_url'];

    return Scaffold(
      appBar: AppBar(
        title: const Text("Edit Profile"),
        backgroundColor: const Color(0xFF00BFA6),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            GestureDetector(
              onTap: pickImage,
              child: CircleAvatar(
                radius: 55,
                backgroundColor: Colors.grey[300],
                backgroundImage: imageFile != null
                    ? FileImage(imageFile!)
                    : (avatar != null ? NetworkImage(avatar) : null)
                as ImageProvider?,
                child: imageFile == null && avatar == null
                    ? const Icon(Icons.camera_alt, size: 40)
                    : null,
              ),
            ),

            const SizedBox(height: 25),

            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: "Full Name",
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 20),

            TextField(
              controller: _phoneCtrl,
              decoration: const InputDecoration(
                labelText: "Phone Number",
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 35),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: isSaving ? null : saveProfile,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00BFA6),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: isSaving
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text("Save Changes"),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
