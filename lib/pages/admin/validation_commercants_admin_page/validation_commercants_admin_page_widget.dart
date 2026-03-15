import '/auth/firebase_auth/auth_util.dart';
import '/backend/backend.dart';
import '/backend/schema/enums/enums.dart';
import '/components/list_empty_component_widget.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_widgets.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class ValidationCommercantsAdminPageWidget extends StatelessWidget {
  const ValidationCommercantsAdminPageWidget({super.key});

  static String routeName = 'ValidationCommercantsAdminPage';
  static String routePath = 'validationCommercantsAdminPage';

  Widget _buildInfoLine(BuildContext context, String label, String value) {
    final displayValue = value.trim().isEmpty ? '-' : value.trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 78.0,
            child: Text('$label :'),
          ),
          Expanded(
            child: Text(displayValue),
          ),
        ],
      ),
    );
  }

  Widget _buildMerchantCard(BuildContext context, UsersRecord user) {
    final theme = FlutterFlowTheme.of(context);
    return Material(
      color: Colors.transparent,
      elevation: 2.0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18.0),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: theme.primaryBackground,
          borderRadius: BorderRadius.circular(18.0),
        ),
        child: Padding(
          padding: const EdgeInsets.all(18.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${user.firstName} ${user.lastName}'.trim(),
                          style: theme.titleMedium.override(
                            font: GoogleFonts.interTight(
                              fontWeight: FontWeight.w700,
                              fontStyle: theme.titleMedium.fontStyle,
                            ),
                            letterSpacing: 0.0,
                            fontWeight: FontWeight.w700,
                            fontStyle: theme.titleMedium.fontStyle,
                          ),
                        ),
                        const SizedBox(height: 4.0),
                        Text(
                          user.email,
                          style: theme.bodySmall.override(
                            font: GoogleFonts.inter(
                              fontWeight: theme.bodySmall.fontWeight,
                              fontStyle: theme.bodySmall.fontStyle,
                            ),
                            color: theme.secondaryText,
                            letterSpacing: 0.0,
                            fontWeight: theme.bodySmall.fontWeight,
                            fontStyle: theme.bodySmall.fontStyle,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0x1AFF8A00),
                      borderRadius: BorderRadius.circular(999.0),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12.0,
                        vertical: 8.0,
                      ),
                      child: Text(
                        'En attente',
                        style: theme.bodySmall.override(
                          font: GoogleFonts.inter(
                            fontWeight: FontWeight.w700,
                            fontStyle: theme.bodySmall.fontStyle,
                          ),
                          color: const Color(0xFFFF6F00),
                          letterSpacing: 0.0,
                          fontWeight: FontWeight.w700,
                          fontStyle: theme.bodySmall.fontStyle,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16.0),
              _buildInfoLine(context, 'Telephone', user.phoneNumber),
              _buildInfoLine(context, 'Ville', user.city),
              const SizedBox(height: 18.0),
              Row(
                children: [
                  Expanded(
                    child: FFButtonWidget(
                      onPressed: () async {
                        await user.reference.update(createUsersRecordData(
                          accountStatus: AccountStatus.rejected,
                        ));
                      },
                      text: 'Refuser',
                      options: FFButtonOptions(
                        width: double.infinity,
                        height: 48.0,
                        color: FlutterFlowTheme.of(context).error,
                        textStyle: theme.titleSmall.override(
                          font: GoogleFonts.interTight(
                            fontWeight: FontWeight.w700,
                            fontStyle: theme.titleSmall.fontStyle,
                          ),
                          color: FlutterFlowTheme.of(context).info,
                          letterSpacing: 0.0,
                          fontWeight: FontWeight.w700,
                          fontStyle: theme.titleSmall.fontStyle,
                        ),
                        elevation: 0.0,
                        borderRadius: BorderRadius.circular(16.0),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12.0),
                  Expanded(
                    child: FFButtonWidget(
                      onPressed: () async {
                        await user.reference.update(createUsersRecordData(
                          accountStatus: AccountStatus.approved,
                        ));
                      },
                      text: 'Valider',
                      options: FFButtonOptions(
                        width: double.infinity,
                        height: 48.0,
                        color: FlutterFlowTheme.of(context).success,
                        textStyle: theme.titleSmall.override(
                          font: GoogleFonts.interTight(
                            fontWeight: FontWeight.w700,
                            fontStyle: theme.titleSmall.fontStyle,
                          ),
                          color: FlutterFlowTheme.of(context).info,
                          letterSpacing: 0.0,
                          fontWeight: FontWeight.w700,
                          fontStyle: theme.titleSmall.fontStyle,
                        ),
                        elevation: 0.0,
                        borderRadius: BorderRadius.circular(16.0),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return Scaffold(
      backgroundColor: theme.secondaryBackground,
      appBar: AppBar(
        title: Text(
          'Validation des commerçants',
          style: theme.titleLarge.override(
            font: GoogleFonts.interTight(
              fontWeight: FontWeight.w700,
              fontStyle: theme.titleLarge.fontStyle,
            ),
            letterSpacing: 0.0,
            fontWeight: FontWeight.w700,
            fontStyle: theme.titleLarge.fontStyle,
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: StreamBuilder<List<UsersRecord>>(
          stream: queryUsersRecord(
            queryBuilder: (usersRecord) => usersRecord
                .where(
                  'account_status',
                  isEqualTo: AccountStatus.pendingValidation.serialize(),
                )
                .where(
                  'user_role',
                  isEqualTo: Roles.commercant.serialize(),
                ),
            limit: 20,
          ),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final pendingUsers = snapshot.data!
                .where((user) => user.uid != currentUserUid)
                .toList();
            if (pendingUsers.isEmpty) {
              return const ListEmptyComponentWidget(
                title: 'Aucune inscription à valider',
                description: 'Liste vide',
              );
            }
            return ListView.separated(
              itemCount: pendingUsers.length,
              separatorBuilder: (_, __) => const SizedBox(height: 16.0),
              itemBuilder: (context, index) =>
                  _buildMerchantCard(context, pendingUsers[index]),
            );
          },
        ),
      ),
    );
  }
}
