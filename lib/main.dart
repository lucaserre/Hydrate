import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'dart:math' as math;
import 'dart:async'; 

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
    await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  
  
  tz_data.initializeTimeZones();
  
  // notificações
  await NotificationService().init();
  
  
  final prefs = await SharedPreferences.getInstance();
  final hydrationData = HydrationData.fromPrefs(prefs);
  
  runApp(
    ChangeNotifierProvider(
      create: (context) => hydrationData,
      child: const HydrationApp(),
    ),
  );
}

class HydrationApp extends StatelessWidget {
  const HydrationApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hydrate - Lembrete de Hidratação',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        brightness: Brightness.light,
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        primarySwatch: Colors.blue,
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
      home: const HomePage(),
    );
  }
}


class HydrationData extends ChangeNotifier {
  int waterGoal = 2500; // meta diaria
  int currentWater = 0; // agua consumida no dia
  List<TimeOfDay> reminderTimes = []; // horario lembrete
  List<bool> reminderEnabled = []; // status dos lembretes
  DateTime lastResetDate = DateTime.now(); // ultimo reset
  
  
  HydrationData();
  
  
  HydrationData.fromPrefs(SharedPreferences prefs) {
    waterGoal = prefs.getInt('waterGoal') ?? 2500;
    currentWater = prefs.getInt('currentWater') ?? 0;
    
   
    final lastResetStr = prefs.getString('lastResetDate');
    if (lastResetStr != null) {
      lastResetDate = DateTime.parse(lastResetStr);
      final now = DateTime.now();
      if (lastResetDate.day != now.day || 
          lastResetDate.month != now.month || 
          lastResetDate.year != now.year) {
        currentWater = 0;
        lastResetDate = DateTime(now.year, now.month, now.day);
      }
    }
    
    
    final remindersJson = prefs.getStringList('reminderTimes') ?? [];
    reminderTimes = remindersJson.map((timeStr) {
      final parts = timeStr.split(':');
      return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
    }).toList();
    
    reminderEnabled = List<bool>.from(
      jsonDecode(prefs.getString('reminderEnabled') ?? '[]') as List? ?? []
    );
    
    
    while (reminderEnabled.length < reminderTimes.length) {
      reminderEnabled.add(true);
    }
  }
  
  
  Future<void> saveToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setInt('waterGoal', waterGoal);
    prefs.setInt('currentWater', currentWater);
    prefs.setString('lastResetDate', lastResetDate.toIso8601String());
    
    
    final remindersJson = reminderTimes.map((time) => 
      '${time.hour}:${time.minute}'
    ).toList();
    prefs.setStringList('reminderTimes', remindersJson);
    
    prefs.setString('reminderEnabled', jsonEncode(reminderEnabled));
  }
  
  
  void addWater(int amount) {
    currentWater += amount;
    checkDailyReset();
    notifyListeners();
    saveToPrefs();
  }

 
void resetWaterCount() {
  currentWater = 0;
  lastResetDate = DateTime.now();
  notifyListeners();
  saveToPrefs();
}
  
 
  void removeWater(int amount) {
    currentWater = (currentWater - amount).clamp(0, waterGoal * 2);
    notifyListeners();
    saveToPrefs();
  }
  
  
  void setWaterGoal(int goal) {
    waterGoal = goal;
    notifyListeners();
    saveToPrefs();
  }
  
  
  void addReminderTime(TimeOfDay time) {
    reminderTimes.add(time);
    reminderEnabled.add(true);
    scheduleNotification(reminderTimes.length - 1);
    notifyListeners();
    saveToPrefs();
  }
  
  
  void removeReminderTime(int index) {
    if (index >= 0 && index < reminderTimes.length) {
      cancelNotification(index);
      reminderTimes.removeAt(index);
      reminderEnabled.removeAt(index);
      notifyListeners();
      saveToPrefs();
    }
  }
  
 
  void updateReminderTime(int index, TimeOfDay newTime) {
    if (index >= 0 && index < reminderTimes.length) {
      reminderTimes[index] = newTime;
      if (reminderEnabled[index]) {
        scheduleNotification(index);
      }
      notifyListeners();
      saveToPrefs();
    }
  }
  
 
  void toggleReminder(int index, bool enabled) {
    if (index >= 0 && index < reminderEnabled.length) {
      reminderEnabled[index] = enabled;
      
      if (enabled) {
        scheduleNotification(index);
      } else {
        cancelNotification(index);
      }
      
      notifyListeners();
      saveToPrefs();
    }
  }
  
  // ponto importante Verificar se é um novo dia e resetar os dados se necessário
  void checkDailyReset() {
    final now = DateTime.now();
    if (lastResetDate.day != now.day || 
        lastResetDate.month != now.month || 
        lastResetDate.year != now.year) {
      currentWater = 0;
      lastResetDate = DateTime(now.year, now.month, now.day);
    }
  }
  
  // ponto importante 
  void scheduleNotification(int index) {
    if (index >= 0 && index < reminderTimes.length) {
      final time = reminderTimes[index];
      NotificationService().scheduleNotification(
        id: index,
        title: "Hora de se hidratar!",
        body: "Não se esqueça de beber água. Seu corpo agradece!",
        time: time,
      );
    }
  }
  
  
  void cancelNotification(int index) {
    NotificationService().cancelNotification(index);
  }
  
  
  void rescheduleAllNotifications() {
    for (int i = 0; i < reminderTimes.length; i++) {
      if (reminderEnabled[i]) {
        scheduleNotification(i);
      }
    }
  }
  
  
  double get progressPercentage => 
    (currentWater / waterGoal).clamp(0.0, 1.0);
}

// gerenciador notificações locias
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();
  
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = 
    FlutterLocalNotificationsPlugin();
    
  Future<void> init() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');
    
    const DarwinInitializationSettings initializationSettingsIOS =
      DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
    
    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
    );
    
    await flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        
      },
    );
    
    // solicitar permissão no iOS
    await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
      ?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
  }
  
  Future<void> scheduleNotification({
    required int id,
    required String title,
    required String body,
    required TimeOfDay time,
  }) async {
    
    final now = DateTime.now();
    var scheduledDate = DateTime(
      now.year,
      now.month,
      now.day,
      time.hour,
      time.minute,
    );
    
    // se o horário de hoje já passou, agendar para amanhã
    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }
    
    // configuração da notificação para Android
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'hydration_channel',
      'Lembretes de Hidratação',
      channelDescription: 'Notificações para lembrar de beber água',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
    );
    
    // configuração da notificação para iOS
    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true, 
      presentSound: true,
    );
    
    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );
    
    // gendar a notificação
    await flutterLocalNotificationsPlugin.zonedSchedule(
      id,
      title,
      body,
      tz.TZDateTime.from(scheduledDate, tz.local),
      notificationDetails,
      androidAllowWhileIdle: true,
      uiLocalNotificationDateInterpretation:
        UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time, // Repetir diariamente
    );
  }
  
  Future<void> cancelNotification(int id) async {
    await flutterLocalNotificationsPlugin.cancel(id);
  }
  
  Future<void> cancelAllNotifications() async {
    await flutterLocalNotificationsPlugin.cancelAll();
  }
}

// tela principal 
class HomePage extends StatefulWidget {
  const HomePage({Key? key}) : super(key: key);

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {

  @override
void initState() {
  super.initState();
  WidgetsBinding.instance.addObserver(this);
  
  
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted) {
      final hydrationData = Provider.of<HydrationData>(context, listen: false);
      hydrationData.checkDailyReset();
      hydrationData.rescheduleAllNotifications();
    }
  });
}

  


  

  void _showAdjustWaterDialog(BuildContext context, HydrationData hydrationData, bool isAdding) {
  final TextEditingController controller = TextEditingController();
  final String action = isAdding ? 'Adicionar' : 'Remover';

  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('$action água'),
      content: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: 'Quantidade (ml)',
          hintText: 'Ex: 250',
          suffixText: 'ml',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        TextButton(
          onPressed: () {
            final amount = int.tryParse(controller.text) ?? 0;
            if (amount > 0) {
              if (isAdding) {
                hydrationData.addWater(amount);
              } else {
                hydrationData.removeWater(amount);
              }
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('$amount ml ${isAdding ? 'adicionados' : 'removidos'}!'),
                  duration: const Duration(seconds: 1),
                ),
              );
            }
          },
          child: Text(action),
        ),
      ],
    ),
  );
}

  void _showResetConfirmationDialog(BuildContext context) {
  final hydrationData = Provider.of<HydrationData>(context, listen: false);
  
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Resetar contagem'),
      content: const Text(
        'Tem certeza que deseja zerar o consumo de água de hoje?'
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        TextButton(
          onPressed: () {
            hydrationData.resetWaterCount();
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Contagem resetada com sucesso!'),
                duration: Duration(seconds: 1),
              ),
            );
          },
          child: const Text('Resetar'),
        ),
      ],
    ),
  );
}
  
  @override
  void dispose() {
  WidgetsBinding.instance.removeObserver(this);
  super.dispose();
}

  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    
    if (state == AppLifecycleState.resumed) {
      final hydrationData = Provider.of<HydrationData>(context, listen: false);
      hydrationData.checkDailyReset();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Hydrate'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsPage()),
              );
            },
          ),
    IconButton(
      icon: const Icon(Icons.refresh),
      tooltip: 'Resetar contagem de água',
      onPressed: () {
        _showResetConfirmationDialog(context);
      },
    ),
  ],
),
      body: SingleChildScrollView(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom + 20),
        child: Column(
          children: [
            const SizedBox(height: 20),
            
            Consumer<HydrationData>(
              builder: (context, hydrationData, child) {
                return WaterBottleWidget(
                  progress: hydrationData.progressPercentage,
                  currentWater: hydrationData.currentWater,
                  waterGoal: hydrationData.waterGoal,
                );
              },
            ),
            
            const SizedBox(height: 30),
            
            // botoes para add agua
            Consumer<HydrationData>(
              builder: (context, hydrationData, child) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '${hydrationData.currentWater} / ${hydrationData.waterGoal} ml',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      
                      const SizedBox(height: 20),
                      
                      

          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.remove),
                onPressed: () {
                  if (hydrationData.currentWater > 0) {
                    _showAdjustWaterDialog(context, hydrationData, false);
                  }
                },
                style: IconButton.styleFrom(
                  backgroundColor: const Color.fromARGB(255, 250, 78, 95),
                ),
              ),
              const SizedBox(width: 20),
              Text(
                'Ajustar\nágua',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(width: 20),
              IconButton(
                icon: const Icon(Icons.add),
                onPressed: () {
                  _showAdjustWaterDialog(context, hydrationData, true);
                },
                style: IconButton.styleFrom(
                  backgroundColor: const Color.fromARGB(255, 49, 107, 155),
                ),
              ),
            ],
          ),
                      
                      
                    
                      
                      const SizedBox(height: 30),
                      
                      // seção de Lembretes
                      const Text(
                        'Meus Lembretes',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      
                      const SizedBox(height: 10),
                      
                      // lista de lembretes
                      _buildRemindersList(context, hydrationData),
                      
                      const SizedBox(height: 10),
                      
                      // botão para add novo lembrete
                      OutlinedButton.icon(
                        icon: const Icon(Icons.add_alarm),
                        label: const Text('Adicionar Novo Lembrete'),
                        onPressed: () => _showTimePickerDialog(context, hydrationData),
                      ),
                    ],
                  ),
                );
              },
            ),
            
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
  

  
  // contrutor da lista de lembrstes
  Widget _buildRemindersList(BuildContext context, HydrationData hydrationData) {
    if (hydrationData.reminderTimes.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Text(
            'Nenhum lembrete configurado.\nAdicione um horário para receber notificações!',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    
    return Card(
      child: ListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: hydrationData.reminderTimes.length,
        itemBuilder: (context, index) {
          final time = hydrationData.reminderTimes[index];
          final isEnabled = hydrationData.reminderEnabled[index];
          
          
          final hour = time.hour.toString().padLeft(2, '0');
          final minute = time.minute.toString().padLeft(2, '0');
          
          return ListTile(
            leading: Icon(
              Icons.access_time,
              color: isEnabled ? Theme.of(context).primaryColor : Colors.grey,
            ),
            title: Text('$hour:$minute'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                
                Switch(
                  value: isEnabled,
                  onChanged: (value) {
                    hydrationData.toggleReminder(index, value);
                  },
                ),
                
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () {
                    hydrationData.removeReminderTime(index);
                  },
                ),
              ],
            ),
            onTap: () {
              
              _showTimePickerDialog(context, hydrationData, index);
            },
          );
        },
      ),
    );
  }
  

  
  
  void _showTimePickerDialog(
    BuildContext context, 
    HydrationData hydrationData,
    [int? editIndex]
  ) async {
    TimeOfDay initialTime = TimeOfDay.now();
    
  
    if (editIndex != null && editIndex >= 0 && 
        editIndex < hydrationData.reminderTimes.length) {
      initialTime = hydrationData.reminderTimes[editIndex];
    }
    
    final TimeOfDay? selectedTime = await showTimePicker(
      context: context,
      initialTime: initialTime,
    );
    
    if (selectedTime != null) {
      if (editIndex != null) {
        
        hydrationData.updateReminderTime(editIndex, selectedTime);
      } else {
        
        hydrationData.addReminderTime(selectedTime);
      }
    }
  }
}

class WaterBottleWidget extends StatefulWidget {
  final double progress;
  final int currentWater;
  final int waterGoal;
  
  const WaterBottleWidget({
    Key? key,
    required this.progress,
    required this.currentWater,
    required this.waterGoal,
  }) : super(key: key);

  @override
  State<WaterBottleWidget> createState() => _WaterBottleWidgetState();
}

class _WaterBottleWidgetState extends State<WaterBottleWidget> {
  
  double _offsetX = 0;
  double _offsetY = 0;
  
  // controlador acelerometro
  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;
  
  // suavizador do movimento
  double _smoothOffsetX = 0;
  double _smoothOffsetY = 0;
  
  @override
  void initState() {
    super.initState();
    print('Inicializando WaterBottleWidget...');
    _startAccelerometer();
  }

  void _startAccelerometer() {
    print('Iniciando acelerômetro...');
    
    
    _accelerometerSubscription?.cancel();
    
    
    _accelerometerSubscription = accelerometerEventStream(
      samplingPeriod: const Duration(milliseconds: 100), // 10 Hz
    ).listen(
      (AccelerometerEvent event) {
        if (!mounted) return;
        

        double newOffsetX = event.x * 8;
        double newOffsetY = -event.y * 12;
        
        
        newOffsetX = newOffsetX.clamp(-25.0, 25.0);
        newOffsetY = newOffsetY.clamp(-30.0, 30.0);
        
        
        _smoothOffsetX += (newOffsetX - _smoothOffsetX) * 0.3;
        _smoothOffsetY += (newOffsetY - _smoothOffsetY) * 0.3;
        
        
        if (((_smoothOffsetX - _offsetX).abs() > 0.5) || 
            ((_smoothOffsetY - _offsetY).abs() > 0.5)) {
          
          setState(() {
            _offsetX = _smoothOffsetX;
            _offsetY = _smoothOffsetY;
          });
        }
      },
      onError: (error) {
        print('Erro no acelerômetro: $error');
      },
    );
  }

  @override
  void dispose() {
    print('Disposing WaterBottleWidget...');
    _accelerometerSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 300,
      width: 200,
      child: Stack(
        alignment: Alignment.center,
        children: [
          
          // Garrafa com água
          CustomPaint(
            size: const Size(160, 280),
            painter: BottlePainter(
              progress: widget.progress,
              offsetX: _offsetX,
              offsetY: _offsetY,
            ),
          ),
          
          // Porcentagem
          Positioned(
            bottom: 30,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${(widget.progress * 100).toInt()}%',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}


class BottlePainter extends CustomPainter {
  final double progress;
  final double offsetX;
  final double offsetY;
  
  BottlePainter({
    required this.progress,
    required this.offsetX,
    required this.offsetY,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double width = size.width;
    final double height = size.height;
    
    
    _drawBottleOutline(canvas, width, height);
    
    
    if (progress > 0) {
      _drawWater(canvas, width, height);
    }
  }

  void _drawBottleOutline(Canvas canvas, double width, double height) {
    final Path bottlePath = Path();
    
    //formato da garrafa
    bottlePath.moveTo(width * 0.3, 0); // topo esquerdo
    bottlePath.lineTo(width * 0.7, 0); // topo direito
    bottlePath.lineTo(width * 0.8, height * 0.1); // ombro direito
    bottlePath.lineTo(width * 0.8, height * 0.9); // lado direito
    bottlePath.quadraticBezierTo(width * 0.8, height, width * 0.5, height); // fundo direito
    bottlePath.quadraticBezierTo(width * 0.2, height, width * 0.2, height * 0.9); // fundo esquerdo
    bottlePath.lineTo(width * 0.2, height * 0.1); // lado esquerdo
    bottlePath.close();
    
    // cor do contorno
    final Paint outlinePaint = Paint()
      ..color = Colors.blue.shade300
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;
    
    canvas.drawPath(bottlePath, outlinePaint);
  }

  void _drawWater(Canvas canvas, double width, double height) {
    
    final Path clipPath = Path();
    clipPath.moveTo(width * 0.3, 0);
    clipPath.lineTo(width * 0.7, 0);
    clipPath.lineTo(width * 0.8, height * 0.1);
    clipPath.lineTo(width * 0.8, height * 0.9);
    clipPath.quadraticBezierTo(width * 0.8, height, width * 0.5, height);
    clipPath.quadraticBezierTo(width * 0.2, height, width * 0.2, height * 0.9);
    clipPath.lineTo(width * 0.2, height * 0.1);
    clipPath.close();

    canvas.save();
    canvas.clipPath(clipPath);
    
    // Calcular nível da água
        double baseWaterLevel = height - (height * progress);

   
    if (offsetY > 15) {
      
      baseWaterLevel = height * 0.1 + (height * (1.0 - progress));
    } else if (offsetY < -15) {
      
      baseWaterLevel = height - (height * progress * 1.2).clamp(0.0, height * 0.9);
    }
    
    
    final double surfaceIncline = offsetX * 3.00; 
    final double leftWaterLevel = baseWaterLevel - surfaceIncline;
    final double rightWaterLevel = baseWaterLevel + surfaceIncline;

    
    final double waterShiftX = offsetX * 0.1; 

    
    final Path waterPath = Path();

    
    final double leftX = (width * 0.2).clamp(width * 0.2, width * 0.8);
    final double rightX = (width * 0.8).clamp(width * 0.2, width * 0.8);
    
    waterPath.moveTo(leftX, leftWaterLevel);
    
    
    final double waveHeight = 4.0;

    
    final double wave1X = leftX + (rightX - leftX) * (1/8);   // 12.5%
    final double wave1Y = leftWaterLevel + (rightWaterLevel - leftWaterLevel) * (1/8);
    final double wave2X = leftX + (rightX - leftX) * (2/8);   // 25%
    final double wave2Y = leftWaterLevel + (rightWaterLevel - leftWaterLevel) * (2/8);
    final double wave3X = leftX + (rightX - leftX) * (3/8);   // 37.5%
    final double wave3Y = leftWaterLevel + (rightWaterLevel - leftWaterLevel) * (3/8);
    final double wave4X = leftX + (rightX - leftX) * (4/8);   // 50%
    final double wave4Y = leftWaterLevel + (rightWaterLevel - leftWaterLevel) * (4/8);
    final double wave5X = leftX + (rightX - leftX) * (5/8);   // 62.5%
    final double wave5Y = leftWaterLevel + (rightWaterLevel - leftWaterLevel) * (5/8);
    final double wave6X = leftX + (rightX - leftX) * (6/8);   // 75%
    final double wave6Y = leftWaterLevel + (rightWaterLevel - leftWaterLevel) * (6/8);
    final double wave7X = leftX + (rightX - leftX) * (7/8);   // 87.5%
    final double wave7Y = leftWaterLevel + (rightWaterLevel - leftWaterLevel) * (7/8);

    
    final double waveOffset1 = math.sin(offsetX * 0.1 + 0 * math.pi/4) * waveHeight;
    final double waveOffset2 = math.sin(offsetX * 0.1 + 1 * math.pi/4) * waveHeight;
    final double waveOffset3 = math.sin(offsetX * 0.1 + 2 * math.pi/4) * waveHeight;
    final double waveOffset4 = math.sin(offsetX * 0.1 + 3 * math.pi/4) * waveHeight;
    final double waveOffset5 = math.sin(offsetX * 0.1 + 4 * math.pi/4) * waveHeight;
    final double waveOffset6 = math.sin(offsetX * 0.1 + 5 * math.pi/4) * waveHeight;
    final double waveOffset7 = math.sin(offsetX * 0.1 + 6 * math.pi/4) * waveHeight;


waterPath.moveTo(leftX, leftWaterLevel);

// onda 1 pra 2
waterPath.quadraticBezierTo(
  wave1X, wave1Y + waveOffset1,
  wave2X, wave2Y + waveOffset2
);

// onda 2 pra 3
waterPath.quadraticBezierTo(
  wave3X, wave3Y + waveOffset3,
  wave4X, wave4Y + waveOffset4
);

// onda 4 pra 5
waterPath.quadraticBezierTo(
  wave5X, wave5Y + waveOffset5,
  wave6X, wave6Y + waveOffset6
);

// onda 6 para 7 e ponto final
waterPath.quadraticBezierTo(
  wave7X, wave7Y + waveOffset7,
  rightX, rightWaterLevel
);
    
    
    waterPath.lineTo(width * 0.8, height * 0.9);
    waterPath.quadraticBezierTo(width * 0.8, height, width * 0.5, height);
    waterPath.quadraticBezierTo(width * 0.2, height, width * 0.2, height * 0.9);
    waterPath.close();
    
    // aguinha gradiente
    final Rect waterRect = Rect.fromLTWH(0, baseWaterLevel, width, height - baseWaterLevel);
    final Paint waterPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.blue.shade200.withOpacity(0.8),
          Colors.blue.shade600.withOpacity(0.9),
        ],
      ).createShader(waterRect);
    
    canvas.drawPath(waterPath, waterPaint);
    
    
    final Paint reflectionPaint = Paint()
      ..color = Colors.white.withOpacity(0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    
    final Path reflectionPath = Path();
    reflectionPath.moveTo(leftX, leftWaterLevel);
    reflectionPath.quadraticBezierTo(
      wave1X, wave1Y + waveOffset1,
      wave2X, wave2Y
      
    );
    reflectionPath.quadraticBezierTo(
      rightX - 10, rightWaterLevel + waveOffset2,
      rightX, rightWaterLevel
    );
    
    canvas.drawPath(reflectionPath, reflectionPaint);
    
    
    if (progress > 0.2) {
      _drawBubbles(canvas, width, height, baseWaterLevel, waterShiftX);
    }
    
    canvas.restore();
  }

  void _drawBubbles(Canvas canvas, double width, double height, double waterLevel, double shiftX) {
    final Paint bubblePaint = Paint()
      ..color = Colors.white.withOpacity(0.6)
      ..style = PaintingStyle.fill;
    
    // bolhas posição
    final List<Offset> bubblePositions = [
      Offset(width * 0.3 + shiftX * 0.8, height - (height * progress * 0.3)),
      Offset(width * 0.6 + shiftX * 1.2, height - (height * progress * 0.6)),
      Offset(width * 0.4 + shiftX * 0.6, height - (height * progress * 0.8)),
      Offset(width * 0.7 + shiftX * 1.0, height - (height * progress * 0.4)),
    ];
    
    for (final pos in bubblePositions) {
    
      if (pos.dy > waterLevel) {
        final double bubbleSize = 2.0 + math.Random().nextDouble() * 3.0;
        canvas.drawCircle(pos, bubbleSize, bubblePaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant BottlePainter oldDelegate) {
    return oldDelegate.progress != progress || 
           (oldDelegate.offsetX - offsetX).abs() > 0.1 || 
           (oldDelegate.offsetY - offsetY).abs() > 0.1;
  }
}


class SettingsPage extends StatefulWidget {
  const SettingsPage({Key? key}) : super(key: key);

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late TextEditingController _goalController;
  
  @override
  void initState() {
    super.initState();
    final hydrationData = Provider.of<HydrationData>(context, listen: false);
    _goalController = TextEditingController(text: hydrationData.waterGoal.toString());
  }
  
  @override
  void dispose() {
    _goalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hydrationData = Provider.of<HydrationData>(context);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Configurações'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Meta Diária de Hidratação',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _goalController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Meta (ml)',
                      hintText: '2500',
                      suffixText: 'ml',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton(
                    onPressed: () {
                      final goal = int.tryParse(_goalController.text) ?? 2500;
                      if (goal > 0) {
                        hydrationData.setWaterGoal(goal);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Meta atualizada com sucesso!'),
                          ),
                        );
                      }
                    },
                    child: const Text('Salvar'),
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Registros de Hidratação',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text('Consumo de hoje: ${hydrationData.currentWater} ml'),
                  Text(
                    'Última atualização: ${_formatDate(hydrationData.lastResetDate)}',
                  ),
                  const SizedBox(height: 10),

                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Sobre o Aplicativo',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Hydrate - Lembrete de Hidratação',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 5),
                  const Text('Versão 1.0.0'),
                  const SizedBox(height: 10),
                  const Text(
                    'Este aplicativo ajuda você a manter-se hidratado durante o dia, '
                    'com lembretes personalizados e acompanhamento do seu consumo de água.',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  
  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} '
      '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}
