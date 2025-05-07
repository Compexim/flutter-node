import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import 'gyarto_parositas.dart'; // szükséges, hogy ismerje a GyartoParositasPageState típust
import 'activity_filter_utils.dart'; // Importáljuk a közös utility fájlt

class UnmatchedSuppliersList extends StatefulWidget {
  final bool isDraggable;
  const UnmatchedSuppliersList({super.key, this.isDraggable = false});

  @override
  State<UnmatchedSuppliersList> createState() => UnmatchedSuppliersListState();
}

class UnmatchedSuppliersListState extends State<UnmatchedSuppliersList> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();

  final Set<String> _selectedSupplierIds = {};

  List<Map<String, dynamic>> suppliers = [];
  int page = 1;
  bool isLoading = false;
  bool hasMore = true;
  // String lastSearch = ''; // Ezt mostantól a _searchController.text adja

  ActivityFilterStatus _supplierActivityFilter =
      ActivityFilterStatus.all; // Szűrő állapota

  @override
  void initState() {
    super.initState();
    _fetchSuppliers(isInitialLoad: true); // Kezdeti betöltés

    _scrollController.addListener(() {
      if (_scrollController.position.pixels >=
              _scrollController.position.maxScrollExtent - 100 &&
          !isLoading &&
          hasMore) {
        _fetchSuppliers();
      }
    });
  }

  void refreshList() {
    _fetchSuppliers(isSearchOrFilterChange: true);
  }

  Future<void> _fetchSuppliers({
    bool isSearchOrFilterChange = false,
    bool isInitialLoad = false,
  }) async {
    if (isLoading && !isInitialLoad)
      return; // Ne fusson párhuzamosan, kivéve ha kezdeti betöltés
    setState(() => isLoading = true);

    if (isSearchOrFilterChange) {
      page = 1;
      suppliers.clear();
      hasMore = true;
    }

    final currentSearchTerm = _searchController.text;
    final String isActiveParam = activityFilterStatusToQueryParam(
      _supplierActivityFilter,
    );
    String apiUrl =
        'http://localhost:3000/api/unmatched-supplier-manufacturers?page=$page&search=${Uri.encodeComponent(currentSearchTerm)}';
    if (isActiveParam.isNotEmpty) {
      apiUrl += '&isActive=$isActiveParam';
    }
    final uri = Uri.parse(apiUrl);

    try {
      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        final newItems =
            data
                .map(
                  (e) => {
                    'id': e['id'],
                    'name': e['name'],
                    'is_active':
                        e['is_active'] ??
                        true, // Alapértelmezett érték, ha a backend nem küldi
                  },
                )
                .toList();

        if (mounted) {
          setState(() {
            suppliers.addAll(newItems);
            page++;
            if (newItems.length < 20) hasMore = false;
          });
        }
      } else {
        debugPrint('Hiba a beszállítók lekérdezésekor: ${response.statusCode}');
        if (mounted) setState(() => hasMore = false);
      }
    } catch (e) {
      debugPrint('API hívás hiba (beszállítók): $e');
      if (mounted) setState(() => hasMore = false);
    }

    if (mounted) {
      setState(() => isLoading = false);
    }
  }

  Future<void> _createManufacturerFromSupplier(
    Map<String, dynamic> supplier,
  ) async {
    final uri = Uri.parse(
      'http://localhost:3000/api/create-and-link-manufacturer',
    );
    try {
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'supplier_manufacturer_id': supplier['id'],
          'name': supplier['name'],
        }),
      );

      if (response.statusCode == 200) {
        final result = json.decode(response.body);
        debugPrint(
          'Sikeres összekötés (új gyártó): ${result['manufacturer_id']}',
        );
        refreshList(); // Frissítjük ezt a listát
        if (mounted) {
          final parent =
              context.findAncestorStateOfType<GyartoParositasPageState>();
          parent?.refreshManufacturers(); // Frissítjük a másik oldalt is
        }
      } else {
        debugPrint('Hiba új gyártó létrehozásakor: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('API hiba új gyártó létrehozásakor: $e');
    }
  }

  Future<void> _deactivateSupplier(Map<String, dynamic> supplier) async {
    final uri = Uri.parse(
      'http://localhost:3000/api/inactivate-supplier-manufacturer',
    );
    try {
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'supplier_manufacturer_id': supplier['id']}),
      );
      if (response.statusCode == 200) {
        debugPrint('Sikeres inaktiválás: ${supplier['id']}');
        refreshList();
      } else {
        debugPrint('Hiba inaktiválásnál: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('API hiba inaktiválásnál: $e');
    }
  }

  Future<void> _bulkCreateSelected() async {
    final selectedSuppliersData =
        suppliers.where((s) => _selectedSupplierIds.contains(s['id'])).toList();
    if (selectedSuppliersData.isEmpty) return;

    // Ideiglenesen inaktívvá tesszük a gombot, amíg a művelet fut
    setState(
      () {},
    ); // Kényszerítjük a UI frissítést, hogy a gomb állapota változzon ha kell

    for (var supplier in selectedSuppliersData) {
      await _createManufacturerFromSupplier(supplier);
    }
    if (mounted) {
      setState(() {
        _selectedSupplierIds.clear();
      });
    }
  }

  void _showContextMenu(
    BuildContext context,
    Offset position,
    Map<String, dynamic> supplier,
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
          value: 'create',
          child: Text('Új saját gyártóként hozzáadás'),
        ),
        if (supplier['is_active'] ==
            true) // Csak akkor jelenítjük meg, ha aktív
          PopupMenuItem<String>(value: 'deactivate', child: Text('Inaktívál')),
        // Ide jöhetne egy "Aktivál" opció is, ha a backend támogatja
      ],
    );

    if (selected == 'create') {
      await _createManufacturerFromSupplier(supplier);
    }
    if (selected == 'deactivate') {
      await _deactivateSupplier(supplier);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
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
                      value: _supplierActivityFilter,
                      isExpanded: true,
                      // hint: Text("Státusz"),
                      onChanged: (ActivityFilterStatus? newValue) {
                        if (newValue != null) {
                          setState(() {
                            _supplierActivityFilter = newValue;
                            refreshList();
                          });
                        }
                      },
                      items:
                          ActivityFilterStatus.values.map((
                            ActivityFilterStatus status,
                          ) {
                            return DropdownMenuItem<ActivityFilterStatus>(
                              value: status,
                              child: Text(statusToString(status)),
                            );
                          }).toList(),
                    ),
                  ),
                ),
              ),
              SizedBox(width: 10),
              ElevatedButton(
                onPressed:
                    _selectedSupplierIds.isNotEmpty
                        ? _bulkCreateSelected
                        : null,
                child: Text('Kijelöltek felvitele'),
                style: ElevatedButton.styleFrom(
                  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 12),
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
              hintText: 'Szűrés beszállítói gyártóra...',
              suffixIcon:
                  _searchController.text.isNotEmpty
                      ? IconButton(
                        icon: Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          refreshList();
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
            onChanged: (value) {
              // Debounce hasznos lehet itt
              refreshList();
            },
            onSubmitted: (_) => refreshList(),
          ),
        ),
        Expanded(
          child:
              suppliers.isEmpty && !isLoading
                  ? Center(
                    child: Text(
                      _searchController.text.isNotEmpty ||
                              _supplierActivityFilter !=
                                  ActivityFilterStatus.all
                          ? 'Nincs a szűrésnek megfelelő találat!'
                          : 'Nincsenek párosítatlan beszállítói gyártók!',
                    ),
                  )
                  : ListView.builder(
                    controller: _scrollController,
                    itemCount: suppliers.length + (hasMore ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index >= suppliers.length) {
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

                      final supplier = suppliers[index];
                      final bool isActive = supplier['is_active'] ?? true;

                      Widget tile = GestureDetector(
                        onSecondaryTapDown: (details) {
                          _showContextMenu(
                            context,
                            details.globalPosition,
                            supplier,
                          );
                        },
                        child: Card(
                          margin: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          color: isActive ? Colors.white : Colors.grey[200],
                          child: ListTile(
                            leading: Checkbox(
                              value: _selectedSupplierIds.contains(
                                supplier['id'],
                              ),
                              onChanged: (checked) {
                                setState(() {
                                  if (checked == true) {
                                    _selectedSupplierIds.add(supplier['id']);
                                  } else {
                                    _selectedSupplierIds.remove(supplier['id']);
                                  }
                                });
                              },
                              activeColor: Theme.of(context).primaryColor,
                            ),
                            title: Text(
                              supplier['name'],
                              style: TextStyle(
                                fontSize: 14,
                                decoration:
                                    isActive
                                        ? TextDecoration.none
                                        : TextDecoration.lineThrough,
                              ),
                            ),
                            trailing:
                                isActive
                                    ? null
                                    : Icon(
                                      Icons.unpublished_outlined,
                                      color: Colors.grey[600],
                                    ),
                          ),
                        ),
                      );

                      if (widget.isDraggable) {
                        tile = Draggable<Map<String, dynamic>>(
                          data: supplier,
                          feedback: Material(
                            elevation: 4.0,
                            child: Container(
                              padding: EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.grey[300],
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                supplier['name'],
                                style: TextStyle(fontSize: 14),
                              ),
                            ),
                          ),
                          childWhenDragging: Opacity(opacity: 0.5, child: tile),
                          child: tile,
                        );
                      }
                      return tile;
                    },
                  ),
        ),
      ],
    );
  }
}
