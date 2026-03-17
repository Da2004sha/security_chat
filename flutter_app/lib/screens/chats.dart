import 'package:flutter/material.dart';
import '../services/api.dart';
import '../services/session.dart';
import 'create_chat.dart';
import 'chat_view.dart';
import 'login.dart';

class ChatsScreen extends StatefulWidget {
  const ChatsScreen({super.key});
  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends State<ChatsScreen> {
  List<Map<String, dynamic>> chats = [];
  bool loading = true;
  String? err;

  Future<void> load() async {
    setState(() { loading = true; err = null; });
    try {
      final res = await Api.instance.getList("/chats");
      chats = res.cast<Map<String, dynamic>>();
      setState(() => loading = false);
    } catch (e) {
      setState(() { err = e.toString(); loading = false; });
    }
  }

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> logout() async {
    await Session.instance.logout();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const LoginScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Chats"),
        actions: [
          IconButton(onPressed: load, icon: const Icon(Icons.refresh)),
          IconButton(onPressed: logout, icon: const Icon(Icons.logout)),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CreateChatScreen()));
          await load();
        },
        child: const Icon(Icons.add),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : err != null
              ? Center(child: Text(err!))
              : ListView.builder(
                  itemCount: chats.length,
                  itemBuilder: (context, i) {
                    final c = chats[i];
                    final title = (c["title"] as String?) ?? "Chat #${c["id"]}";
                    return ListTile(
                      title: Text(title),
                      subtitle: Text((c["is_group"] as bool) ? "Group" : "Direct"),
                      onTap: () {
                        Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => ChatViewScreen(chatId: c["id"] as int, title: title),
                        ));
                      },
                    );
                  },
                ),
    );
  }
}
