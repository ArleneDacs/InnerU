import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:selfcare_projects/src/features/authentication/screen/UsersData/user_service.dart';
import 'package:selfcare_projects/src/services/auth_service.dart';
import 'package:selfcare_projects/src/services/company_theme_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class StepGoalScreen extends StatefulWidget {
  const StepGoalScreen({super.key, this.initialGoal});

  final int? initialGoal;

  @override
  State<StepGoalScreen> createState() => _StepGoalScreenState();
}

class _StepGoalScreenState extends State<StepGoalScreen> {
  final TextEditingController _goalController = TextEditingController();
  final List<int> _quickGoals = const [3000, 5000, 8000, 10000, 12000];

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialGoal != null && widget.initialGoal! > 0) {
      _goalController.text = widget.initialGoal.toString();
    }
  }

  @override
  void dispose() {
    _goalController.dispose();
    super.dispose();
  }

  Future<void> _saveGoal() async {
    final session = AuthService.instance.currentSession;
    final int? parsedGoal = int.tryParse(_goalController.text.trim());
    var didPop = false;

    if (session == null || parsedGoal == null) {
      _showError('Enter a valid step goal first.');
      return;
    }

    if (parsedGoal < 1000 || parsedGoal > 50000) {
      _showError('Choose a goal between 1,000 and 50,000 steps.');
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      await UserService.updateUserFields({
        'daily_step_goal': parsedGoal,
      });

      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('daily_step_goal_${session.id}', parsedGoal);

      if (!mounted) return;
      didPop = true;
      Navigator.pop(context, parsedGoal);
    } catch (e) {
      _showError('Failed to save your step goal. Please try again.');
    } finally {
      if (mounted && !didPop) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CompanyThemeBuilder(
      builder: (context, companyTheme) {
        return Scaffold(
          backgroundColor: companyTheme.backgroundColor,
          appBar: AppBar(
            backgroundColor: companyTheme.surfaceColor,
            foregroundColor: companyTheme.inkColor,
            iconTheme: IconThemeData(color: companyTheme.inkColor),
            surfaceTintColor: Colors.transparent,
            title: Text(
              'Step Goal',
              style: TextStyle(
                color: companyTheme.inkColor,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: companyTheme.isDark
                          ? companyTheme.surfaceColor
                          : const Color(0xFFFCF5EA),
                      borderRadius: BorderRadius.circular(20),
                      border: companyTheme.isDark
                          ? Border.all(
                              color: companyTheme.primaryColor
                                  .withValues(alpha: 0.18),
                            )
                          : null,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Set your target steps',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: companyTheme.inkColor,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Choose a daily walking goal that feels realistic and motivating for you.',
                          style: TextStyle(
                            fontSize: 15,
                            color: companyTheme.mutedInkColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Daily step goal',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: companyTheme.inkColor,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _goalController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      hintText: 'Enter your goal',
                      suffixText: 'steps',
                      filled: true,
                      fillColor: companyTheme.isDark
                          ? companyTheme.surfaceColor
                          : const Color(0xFFFFECC9),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: companyTheme.isDark
                            ? BorderSide(
                                color: companyTheme.primaryColor
                                    .withValues(alpha: 0.2),
                              )
                            : BorderSide.none,
                      ),
                    ),
                    style: TextStyle(color: companyTheme.inkColor),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Quick picks',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: companyTheme.inkColor,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: _quickGoals.map((goal) {
                      return ChoiceChip(
                        label: Text('$goal'),
                        selected: _goalController.text == goal.toString(),
                        onSelected: (_) {
                          setState(() {
                            _goalController.text = goal.toString();
                          });
                        },
                      );
                    }).toList(),
                  ),
                  const Spacer(),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _saveGoal,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: companyTheme.primaryColor,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: _isSaving
                          ? const SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'Save Goal',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
