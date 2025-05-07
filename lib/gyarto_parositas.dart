import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;

import 'unmatched_suppliers_list.dart';
import 'activity_filter_utils.dart'; // Importáljuk a közös utility fájlt

class GyartoParositasPage extends StatefulWidget {
  const GyartoParositasPage({super.key});

  @override
  State<GyartoParositasPage> createState() => GyartoParositasPageState();
}

class GyartoParositasPageState extends State<GyartoParositasPage> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  final GlobalKey<UnmatchedSuppliersListState> _suppliersListKey = GlobalKey();
  Timer? _debounceSearch;

  List<Map<String, dynamic>> manufacturers = [];
  int page = 1;
  bool isLoading = false;
  bool hasMore = true;

  Map<String, bool> editing = {};
  Map<String, TextEditingController> controllers = {};

  ActivityFilterStatus _manufacturerActivityFilter =
      ActivityFilterStatus.all; // Szűrő állapota

  @override
  void initState() {
    super.initState();
    _fetchManufacturers(isInitialLoad: true);

    _scrollController.addListener(() {
      if (_scrollController.position.pixels >=
              _scrollController.position.maxScrollExtent - 100 &&
          !isLoading &&
          hasMore) {
        _fetchManufacturers();
      }
    });
  }

  void refreshManufacturers() {
    // Nem kell setState itt, mert a _fetchManufacturers már kezeli
    _fetchManufacturers(isSearchOrFilterChange: true);
  }

  Future<void> _fetchManufacturers({
    bool isSearchOrFilterChange = false,
    bool isInitialLoad = false,
  }) async {
    if (isLoading && !isInitialLoad) return;
    setState(() => isLoading = true);

    if (isSearchOrFilterChange) {
      page = 1;
      manufacturers.clear();
      hasMore = true;
    }

    final currentSearchTerm = _searchController.text;
    final String isActiveParam = activityFilterStatusToQueryParam(
      _manufacturerActivityFilter,
    );
    String apiUrl =
        'http://localhost:3000/api/manufacturers-with-aliases?page=$page&search=${Uri.encodeComponent(currentSearchTerm)}';
    if (isActiveParam.isNotEmpty) {
      apiUrl += '&isActive=$isActiveParam';
    }
    final uri = Uri.parse(apiUrl);

    try {
      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        final List<Map<String, dynamic>> newItems =
            data.map((item) {
              final aliasesRaw = item['aliases'];
              final List<Map<String, dynamic>> aliasesList =
                  aliasesRaw is List
                      ? aliasesRaw
                          .where((e) => e != null && e is Map<String, dynamic>)
                          .map(
                            (e) => {
                              'id': e['id'],
                              'name': e['name'],
                              'is_active': e['is_active'] ?? true,
                            },
                          )
                          .toList()
                      : [];

              return {
                'id': item['id'],
                'name': item['name'],
                'aliases': aliasesList,
                'has_exact_match': item['has_exact_match'] ?? false,
                'is_active': item['is_active'] ?? true,
              };
            }).toList();

        if (mounted) {
          setState(() {
            manufacturers.addAll(newItems);
            page++;
            if (newItems.length < 20) hasMore = false;
            for (var item in newItems) {
              final id = item['id'] as String;
              if (!editing.containsKey(id)) editing[id] = false;
              if (!controllers.containsKey(id)) {
                controllers[id] = TextEditingController(text: item['name']);
              } else {
                controllers[id]!.text = item['name'];
              }
            }
          });
        }
      } else {
        debugPrint('Hibás API válasz (gyártók): ${response.statusCode}');
        if (mounted) setState(() => hasMore = false);
      }
    } catch (e) {
      debugPrint('API hívás hiba (gyártók): $e');
      if (mounted) setState(() => hasMore = false);
    }
    if (mounted) {
      setState(() => isLoading = false);
    }
  }

  void _onSearchChanged(String query) {
    if (_debounceSearch?.isActive ?? false) _debounceSearch!.cancel();
    _debounceSearch = Timer(const Duration(milliseconds: 400), () {
      _fetchManufacturers(isSearchOrFilterChange: true);
    });
  }

  Future<void> _pairManufacturer(
    String supplierId,
    String manufacturerId,
  ) async {
    final uri = Uri.parse('http://localhost:3000/api/pair-manufacturer');
    try {
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'supplier_manufacturer_id': supplierId,
          'manufacturer_id': manufacturerId,
        }),
      );

      if (response.statusCode == 200) {
        debugPrint('Párosítás sikeres');
        refreshManufacturers();
        _suppliersListKey.currentState?.refreshList();
      } else {
        debugPrint('Hiba a párosításkor: ${response.statusCode}');
        // Itt lehetne egy Snackbar visszajelzés a felhasználónak
      }
    } catch (e) {
      debugPrint('API hiba a párosításkor: $e');
    }
  }

  Future<void> _updateManufacturer(String id, String newName) async {
    final uri = Uri.parse('http://localhost:3000/api/update-manufacturer-name');
    try {
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'manufacturer_id': id, 'new_name': newName}),
      );
      if (response.statusCode == 200) {
        debugPrint('Gyártó frissítve');
        if (mounted) {
          setState(() {
            editing[id] = false;
            final index = manufacturers.indexWhere((m) => m['id'] == id);
            if (index != -1) {
              manufacturers[index]['name'] = newName;
            }
          });
        }
      } else {
        debugPrint('Gyártó frissítés sikertelen: ${response.statusCode}');
        // Visszaállítjuk az eredeti nevet, ha a szerkesztés nem sikerült
        if (mounted) {
          setState(() {
            editing[id] = false;
            // controllers[id]?.text = manufacturers.firstWhere((m) => m['id'] == id)['name'];
          });
        }
      }
    } catch (e) {
      debugPrint('Gyártó frissítés hiba: $e');
      if (mounted) {
        setState(() {
          editing[id] = false;
        });
      }
    }
  }

  Future<void> _unpairAll(String manufacturerId) async {
    try {
      final response = await http.post(
        Uri.parse('http://localhost:3000/api/unpair-all'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'manufacturer_id': manufacturerId}),
      );
      if (response.statusCode == 200) {
        refreshManufacturers();
        _suppliersListKey.currentState?.refreshList();
      } else {
        debugPrint('Minden leválasztása sikertelen: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Hiba minden leválasztása közben: $e');
    }
  }

  Future<void> _unpairAlias(String supplierManufacturerId) async {
    try {
      final response = await http.post(
        Uri.parse('http://localhost:3000/api/unpair-alias'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'supplier_manufacturer_id': supplierManufacturerId}),
      );
      if (response.statusCode == 200) {
        refreshManufacturers();
        _suppliersListKey.currentState?.refreshList();
      } else {
        debugPrint('Alias leválasztása sikertelen: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Hiba alias leválasztás közben: $e');
    }
  }

  Future<void> _toggleManufacturerActiveState(
    String manufacturerId,
    bool currentIsActive,
  ) async {
    // Ez a végpont még nincs implementálva a backendben, de itt lenne a helye
    // A backendnek tudnia kell váltani az is_active állapotot.
    // Példa: POST /api/toggle-manufacturer-active {'manufacturer_id': manufacturerId}
    // Sikeres válasz után: refreshManufacturers();
    debugPrint("Backend végpont hiányzik a gyártó aktiv/inaktív váltásához.");

    // DEMO - Csak UI frissítés, backend nélkül NEM MARADANDÓ
    // final index = manufacturers.indexWhere((m) => m['id'] == manufacturerId);
    // if (index != -1) {
    //   setState(() {
    //     manufacturers[index]['is_active'] = !currentIsActive;
    //   });
    // }
  }

  Widget _buildManufacturerCard(Map<String, dynamic> manufacturer) {
    final name = manufacturer['name'] as String;
    final aliases = manufacturer['aliases'] as List<Map<String, dynamic>>;
    final id = manufacturer['id'] as String;
    final hasExactMatch = manufacturer['has_exact_match'] == true;
    final bool isActive = manufacturer['is_active'] ?? true;

    void showManufacturerMenu(BuildContext context, Offset position) async {
      final selected = await showMenu<String>(
        context: context,
        position: RelativeRect.fromLTRB(
          position.dx,
          position.dy,
          position.dx,
          position.dy,
        ),
        items: [
          PopupMenuItem<String>(
            value: 'unpair_all',
            child: Text('Gyártó + Aliasok leválasztása'),
          ),
          PopupMenuItem<String>(
            // ÚJ
            value: 'toggle_active',
            child: Text(isActive ? 'Inaktíválás' : 'Aktiválás'),
          ),
        ],
      );

      if (selected == 'unpair_all') {
        await _unpairAll(id);
      } else if (selected == 'toggle_active') {
        await _toggleManufacturerActiveState(id, isActive);
      }
    }

    void showAliasMenu(
      BuildContext context,
      Offset position,
      Map<String, dynamic> alias,
    ) async {
      final selected = await showMenu<String>(
        context: context,
        position: RelativeRect.fromLTRB(
          position.dx,
          position.dy,
          position.dx,
          position.dy,
        ),
        items: [
          PopupMenuItem<String>(
            value: 'unpair_one',
            child: Text('Alias leválasztása'),
          ),
        ],
      );

      if (selected == 'unpair_one') {
        await _unpairAlias(alias['id']);
      }
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      color: isActive ? Colors.white : Colors.grey[200],
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: () {
                if (isActive) {
                  // Csak aktív gyártót lehessen szerkeszteni
                  setState(() {
                    editing[id] = true;
                    controllers[id]?.text = name;
                  });
                }
              },
              onSecondaryTapDown:
                  (details) =>
                      showManufacturerMenu(context, details.globalPosition),
              child:
                  editing[id] == true && isActive
                      ? TextField(
                        controller: controllers[id],
                        autofocus: true,
                        decoration: InputDecoration(isDense: true),
                        onSubmitted: (value) {
                          if (value.trim().isNotEmpty) {
                            _updateManufacturer(id, value.trim());
                          } else {
                            setState(() => editing[id] = false);
                          }
                        },
                        onEditingComplete: () {
                          // Ha kiveszi a fókuszt
                          final newName = controllers[id]?.text.trim() ?? '';
                          if (newName.isNotEmpty && newName != name) {
                            _updateManufacturer(id, newName);
                          } else {
                            setState(() => editing[id] = false);
                          }
                        },
                      )
                      : Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              name,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                                color:
                                    isActive
                                        ? Color(0xFF111827)
                                        : Colors.grey[700],
                                decoration:
                                    isActive
                                        ? TextDecoration.none
                                        : TextDecoration.lineThrough,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (hasExactMatch && isActive)
                            Icon(
                              Icons.link,
                              size: 16,
                              color: Color(0xFF6C5DD3),
                            ),
                          if (!isActive)
                            Icon(
                              Icons.unpublished_outlined,
                              size: 16,
                              color: Colors.grey[700],
                            ),
                        ],
                      ),
            ),
            if (aliases.isNotEmpty) ...[
              SizedBox(height: isActive ? 4 : 2),
              Wrap(
                spacing: 6.0,
                runSpacing: 4.0,
                children:
                    aliases.map((alias) {
                      final bool aliasIsActive = alias['is_active'] ?? true;
                      return GestureDetector(
                        onSecondaryTapDown:
                            (details) => showAliasMenu(
                              context,
                              details.globalPosition,
                              alias,
                            ),
                        child: Chip(
                          label: Text(
                            alias['name'],
                            style: TextStyle(
                              fontSize: 11,
                              color:
                                  aliasIsActive
                                      ? Colors.green[800]
                                      : Colors.grey[600],
                              decoration:
                                  aliasIsActive
                                      ? TextDecoration.none
                                      : TextDecoration.lineThrough,
                            ),
                          ),
                          backgroundColor:
                              aliasIsActive
                                  ? Colors.green[50]
                                  : Colors.grey[300],
                          padding: EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 0,
                          ),
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          labelPadding: EdgeInsets.only(left: 4, right: 4),
                        ),
                      );
                    }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _debounceSearch?.cancel();
    _scrollController.dispose();
    _searchController.dispose();
    for (var controller in controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 40,
        title: Text(
          'Gyártók párosítása',
          style: TextStyle(
            fontSize: 18,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        backgroundColor:
            Theme.of(context).appBarTheme.backgroundColor ??
            Theme.of(context).colorScheme.surfaceVariant,
        elevation: 1,
      ),
      body: Row(
        children: [
          Expanded(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Row(
                    children: [
                      Expanded(
                        child: DropdownButtonHideUnderline(
                          child: Container(
                            padding: EdgeInsets.symmetric(horizontal: 10.0),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(5.0),
                              border: Border.all(
                                color: Colors.grey.shade400,
                                style: BorderStyle.solid,
                                width: 0.80,
                              ),
                            ),
                            child: DropdownButton<ActivityFilterStatus>(
                              value: _manufacturerActivityFilter,
                              isExpanded: true,
                              // hint: Text("Státusz"),
                              onChanged: (ActivityFilterStatus? newValue) {
                                if (newValue != null) {
                                  setState(() {
                                    _manufacturerActivityFilter = newValue;
                                    refreshManufacturers();
                                  });
                                }
                              },
                              items:
                                  ActivityFilterStatus.values.map((
                                    ActivityFilterStatus status,
                                  ) {
                                    return DropdownMenuItem<
                                      ActivityFilterStatus
                                    >(
                                      value: status,
                                      child: Text(statusToString(status)),
                                    );
                                  }).toList(),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8.0, 0, 8.0, 8.0),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Szűrés saját gyártóra vagy aliasra...',
                      suffixIcon:
                          _searchController.text.isNotEmpty
                              ? IconButton(
                                icon: Icon(Icons.clear),
                                onPressed: () {
                                  _searchController.clear();
                                  _onSearchChanged(
                                    '',
                                  ); // Hogy a debounce lefusson üres stringgel
                                },
                              )
                              : null,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(5.0),
                      ),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 10.0,
                        vertical: 8.0,
                      ),
                    ),
                    onChanged: _onSearchChanged,
                  ),
                ),
                Expanded(
                  child:
                      manufacturers.isEmpty && !isLoading
                          ? Center(
                            child: Text(
                              _searchController.text.isNotEmpty ||
                                      _manufacturerActivityFilter !=
                                          ActivityFilterStatus.all
                                  ? 'Nincs a szűrésnek megfelelő találat!'
                                  : 'Nincsenek gyártók!',
                            ),
                          )
                          : ListView.builder(
                            controller: _scrollController,
                            itemCount: manufacturers.length + (hasMore ? 1 : 0),
                            itemBuilder: (context, index) {
                              if (index >= manufacturers.length) {
                                return Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(16.0),
                                    child:
                                        isLoading
                                            ? CircularProgressIndicator()
                                            : SizedBox.shrink(),
                                  ),
                                );
                              }
                              final manufacturer = manufacturers[index];
                              return DragTarget<Map<String, dynamic>>(
                                onWillAcceptWithDetails: (data) => true,
                                onAcceptWithDetails: (
                                  DragTargetDetails<Map<String, dynamic>>
                                  details,
                                ) async {
                                  final supplier = details.data;
                                  await _pairManufacturer(
                                    supplier['id'].toString(),
                                    manufacturer['id'],
                                  );
                                },
                                builder: (
                                  context,
                                  candidateData,
                                  rejectedData,
                                ) {
                                  return _buildManufacturerCard(manufacturer);
                                },
                              );
                            },
                          ),
                ),
              ],
            ),
          ),
          const VerticalDivider(width: 1, thickness: 1),
          Expanded(
            child: UnmatchedSuppliersList(
              key: _suppliersListKey,
              isDraggable: true,
            ),
          ),
        ],
      ),
    );
  }
}
