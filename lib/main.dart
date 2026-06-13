import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:http/http.dart' as http;
import 'package:window_manager/window_manager.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

final GlobalKey<_ChatOverlayScreenState> chatOverlayKey =
    GlobalKey<_ChatOverlayScreenState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await windowManager.ensureInitialized();
  await hotKeyManager.unregisterAll();

  final windowOptions = WindowOptions(
    size: const Size(430, 560),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: true,
    titleBarStyle: TitleBarStyle.hidden,
  );

  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.setAlwaysOnTop(true);
    await windowManager.hide();
  });

  runApp(const AiOverlayApp());
}

class AiOverlayApp extends StatefulWidget {
  const AiOverlayApp({super.key});

  @override
  State<AiOverlayApp> createState() => _AiOverlayAppState();
}

class _AiOverlayAppState extends State<AiOverlayApp> {
  HotKey? _toggleHotKey;
  HotKey? _clipboardHotKey;

  @override
  void initState() {
    super.initState();
    _registerShortcuts();
  }

  Future<void> _showOverlay() async {
    await windowManager.show();
    await windowManager.focus();
    await windowManager.setAlwaysOnTop(true);
  }

  Future<void> _registerShortcuts() async {
    _toggleHotKey = HotKey(
      key: PhysicalKeyboardKey.space,
      modifiers: [HotKeyModifier.control],
      scope: HotKeyScope.system,
    );

    _clipboardHotKey = HotKey(
      key: PhysicalKeyboardKey.space,
      modifiers: [HotKeyModifier.control, HotKeyModifier.shift],
      scope: HotKeyScope.system,
    );

    await hotKeyManager.register(
      _toggleHotKey!,
      keyDownHandler: (_) async {
        final isVisible = await windowManager.isVisible();

        if (isVisible) {
          await windowManager.hide();
        } else {
          await _showOverlay();
        }
      },
    );

    await hotKeyManager.register(
      _clipboardHotKey!,
      keyDownHandler: (_) async {
        await _showOverlay();

        await Future.delayed(const Duration(milliseconds: 100));

        await chatOverlayKey.currentState?.askFromClipboard();
      },
    );
  }

  @override
  void dispose() {
    if (_toggleHotKey != null) {
      hotKeyManager.unregister(_toggleHotKey!);
    }

    if (_clipboardHotKey != null) {
      hotKeyManager.unregister(_clipboardHotKey!);
    }

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: ChatOverlayScreen(key: chatOverlayKey),
    );
  }
}

class ChatOverlayScreen extends StatefulWidget {
  const ChatOverlayScreen({super.key});

  @override
  State<ChatOverlayScreen> createState() => _ChatOverlayScreenState();
}

class _ChatOverlayScreenState extends State<ChatOverlayScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  Widget _buildQuickActions() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: Colors.white.withOpacity(0.03),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _quickActionButton(
              label: 'Explain',
              icon: Icons.lightbulb_outline,
              action: ClipboardAction.explain,
            ),
            _quickActionButton(
              label: 'Debug',
              icon: Icons.bug_report_outlined,
              action: ClipboardAction.debug,
            ),
            _quickActionButton(
              label: 'Summarize',
              icon: Icons.subject,
              action: ClipboardAction.summarize,
            ),
            _quickActionButton(
              label: 'Make Notes',
              icon: Icons.note_alt_outlined,
              action: ClipboardAction.notes,
            ),
          ],
        ),
      ),
    );
  }

  Widget _quickActionButton({
    required String label,
    required IconData icon,
    required ClipboardAction action,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: TextButton.icon(
        onPressed: () => askFromClipboard(action: action),
        icon: Icon(icon, size: 16, color: Colors.white),
        label: Text(label, style: const TextStyle(color: Colors.white)),
        style: TextButton.styleFrom(
          backgroundColor: Colors.white.withOpacity(0.08),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  Future<void> _sendDirectPrompt({
    required String displayText,
    required String prompt,
  }) async {
    if (_loading) return;

    setState(() {
      _messages.add(ChatMessage(role: MessageRole.user, text: displayText));
      _loading = true;
    });

    _scrollToBottom();

    try {
      final reply = await GeminiService.ask(prompt);

      setState(() {
        _messages.add(ChatMessage(role: MessageRole.assistant, text: reply));
      });
    } catch (e) {
      setState(() {
        _messages.add(
          ChatMessage(role: MessageRole.assistant, text: 'Error: $e'),
        );
      });
    } finally {
      setState(() {
        _loading = false;
      });

      _scrollToBottom();
    }
  }

  String _buildClipboardPrompt(String copiedText, ClipboardAction action) {
    switch (action) {
      case ClipboardAction.explain:
        return '''
Explain this clearly and simply. If it is code, explain what each important part does:

$copiedText
''';

      case ClipboardAction.debug:
        return '''
Check this carefully for bugs, errors, bad logic, or improvements.
If it is code, explain the issue and give the corrected version:

$copiedText
''';

      case ClipboardAction.summarize:
        return '''
Summarize this in simple points. Keep only the important ideas:

$copiedText
''';

      case ClipboardAction.notes:
        return '''
Convert this into clean study notes with headings, bullet points, and important keywords:

$copiedText
''';
    }
  }

  Future<void> askFromClipboard({
    ClipboardAction action = ClipboardAction.explain,
  }) async {
    final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
    final copiedText = clipboardData?.text?.trim();

    if (copiedText == null || copiedText.isEmpty) {
      setState(() {
        _messages.add(
          ChatMessage(
            role: MessageRole.assistant,
            text: 'Clipboard is empty. Copy some text/code first.',
          ),
        );
      });

      _scrollToBottom();
      return;
    }

    final prompt = _buildClipboardPrompt(copiedText, action);

    String displayText;

    switch (action) {
      case ClipboardAction.explain:
        displayText = 'Explain clipboard content';
        break;
      case ClipboardAction.debug:
        displayText = 'Debug clipboard content';
        break;
      case ClipboardAction.summarize:
        displayText = 'Summarize clipboard content';
        break;
      case ClipboardAction.notes:
        displayText = 'Make notes from clipboard content';
        break;
    }

    await _sendDirectPrompt(displayText: displayText, prompt: prompt);
  }

  final List<ChatMessage> _messages = [
    ChatMessage(
      role: MessageRole.assistant,
      text: 'Hey Aryan 👋 Ask me anything.',
    ),
  ];

  bool _loading = false;

  Future<void> _sendMessage() async {
    final userText = _controller.text.trim();

    if (userText.isEmpty || _loading) return;

    setState(() {
      _messages.add(ChatMessage(role: MessageRole.user, text: userText));
      _controller.clear();
      _loading = true;
    });

    _scrollToBottom();

    try {
      final reply = await GeminiService.ask(userText);

      setState(() {
        _messages.add(ChatMessage(role: MessageRole.assistant, text: reply));
      });
    } catch (e) {
      setState(() {
        _messages.add(
          ChatMessage(role: MessageRole.assistant, text: 'Error: $e'),
        );
      });
    } finally {
      setState(() {
        _loading = false;
      });

      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (!_scrollController.hasClients) return;

      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _closeOverlay() async {
    await windowManager.hide();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Padding(
        padding: const EdgeInsets.all(14),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF111827).withOpacity(0.96),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Colors.white.withOpacity(0.12)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.35),
                  blurRadius: 22,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              children: [
                _buildTitleBar(),
                Expanded(child: _buildChatList()),
                _buildQuickActions(),
                if (_loading) _buildTypingIndicator(),
                _buildInputBar(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTitleBar() {
    return GestureDetector(
      onPanStart: (_) async {
        await windowManager.startDragging();
      },
      child: Container(
        height: 54,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        color: Colors.white.withOpacity(0.05),
        child: Row(
          children: [
            const Icon(Icons.auto_awesome, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'AI Overlay Assistant',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            IconButton(
              onPressed: _closeOverlay,
              icon: const Icon(Icons.close, color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChatList() {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(14),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final message = _messages[index];
        final isUser = message.role == MessageRole.user;

        return Align(
          alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            constraints: const BoxConstraints(maxWidth: 330),
            decoration: BoxDecoration(
              color: isUser
                  ? const Color(0xFF2563EB)
                  : Colors.white.withOpacity(0.09),
              borderRadius: BorderRadius.circular(14),
            ),
            child: isUser
                ? SelectableText(
                    message.text,
                    textAlign: TextAlign.left,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      height: 1.4,
                    ),
                  )
                : MarkdownBody(
                    data: message.text,
                    selectable: true,
                    styleSheet: MarkdownStyleSheet(
                      p: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        height: 1.45,
                      ),
                      h1: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                      h2: const TextStyle(
                        color: Colors.white,
                        fontSize: 19,
                        fontWeight: FontWeight.bold,
                      ),
                      h3: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      listBullet: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                      ),
                      code: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontFamily: 'Consolas',
                        backgroundColor: Color(0xFF1F2937),
                      ),
                      codeblockDecoration: BoxDecoration(
                        color: const Color(0xFF1F2937),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      blockquote: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                  ),
          ),
        );
      },
    );
  }

  Widget _buildTypingIndicator() {
    return const Padding(
      padding: EdgeInsets.only(bottom: 8),
      child: Text(
        'Thinking...',
        style: TextStyle(color: Colors.white54, fontSize: 12),
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.all(12),
      color: Colors.white.withOpacity(0.04),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              style: const TextStyle(color: Colors.white),
              minLines: 1,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: 'Ask something...',
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: Colors.white.withOpacity(0.08),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
              onSubmitted: (_) => _sendMessage(),
            ),
          ),
          const SizedBox(width: 10),
          IconButton(
            onPressed: _sendMessage,
            icon: const Icon(Icons.send, color: Colors.white),
            style: IconButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              padding: const EdgeInsets.all(14),
            ),
          ),
        ],
      ),
    );
  }
}

class GeminiService {
  static const String _apiKey = String.fromEnvironment('GEMINI_API_KEY');

  static Future<String> ask(String prompt) async {
    if (_apiKey.isEmpty) {
      throw Exception(
        'Missing API key. Run with --dart-define=GEMINI_API_KEY=your_key',
      );
    }

    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-3.5-flash:generateContent',
    );

    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json', 'x-goog-api-key': _apiKey},
      body: jsonEncode({
        'contents': [
          {
            'parts': [
              {'text': prompt},
            ],
          },
        ],
      }),
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Gemini API failed: ${response.statusCode} ${response.body}',
      );
    }

    final Map<String, dynamic> data = jsonDecode(response.body);

    final candidates = data['candidates'] as List<dynamic>?;

    if (candidates == null || candidates.isEmpty) {
      return 'No response received.';
    }

    final content = candidates.first['content'] as Map<String, dynamic>?;
    final parts = content?['parts'] as List<dynamic>?;

    if (parts == null || parts.isEmpty) {
      return 'No text found in response.';
    }

    return parts.map((part) => part['text'] ?? '').join('\n').trim();
  }
}

enum ClipboardAction { explain, debug, summarize, notes }

enum MessageRole { user, assistant }

class ChatMessage {
  final MessageRole role;
  final String text;

  ChatMessage({required this.role, required this.text});
}
