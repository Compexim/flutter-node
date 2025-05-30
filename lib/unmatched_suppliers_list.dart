import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import 'gyarto_parositas.dart'; // szükséges, hogy ismerje a GyartoParositasPageState típust

class UnmatchedSuppliersList extends StatefulWidget {
  final bool isDraggable;
  const UnmatchedSuppliersList({super.key, this.isDraggable = false});

  @override
  State<UnmatchedSuppliersList> createState() => UnmatchedSuppliersListState();
}

class UnmatchedSuppliersListState extends State<UnmatchedSuppliersList> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();

  // Selected supplier IDs for bulk actions
  final Set<String> _selectedSupplierIds = {};

  List<Map<String, dynamic>> suppliers = [];
  int page = 1;
  bool isLoading = false;
  bool hasMore = true;
  String lastSearch = '';

  @override
  void initState() {
    super.initState();
    _fetchSuppliers();

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
    _fetchSuppliers(isSearch: true);
  }

  Future<void> _fetchSuppliers({bool isSearch = false}) async {
    setState(() => isLoading = true);

    if (isSearch) {
      page = 1;
      suppliers.clear();
      hasMore = true;
      lastSearch = _searchController.text;
    }

    final uri = Uri.parse(
      'http://localhost:3000/api/unmatched-supplier-manufacturers?page=$page&search=$lastSearch',
    );

    try {
      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);

        final newItems =
            data.map((e) => {'id': e['id'], 'name': e['name']}).toList();

        setState(() {
          suppliers.addAll(newItems);
          page++;
          if (newItems.length < 20) hasMore = false;
        });
      } else {
        print('Hiba: ${response.statusCode}');
      }
    } catch (e) {
      print('API hívás hiba: $e');
    }

    setState(() => isLoading = false);
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
        PopupMenuItem<String>(value: 'deactivate', child: Text('Inaktívál')),
      ],
    );

    if (selected == 'create') {
      await _createManufacturerFromSupplier(supplier);
    }
    if (selected == 'deactivate') {
      await _deactivateSupplier(supplier);
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
        debugPrint('Sikeres összekötés: ${result['manufacturer_id']}');

        refreshList();

        if (mounted) {
          final parent =
              context.findAncestorStateOfType<GyartoParositasPageState>();
          parent?.refreshManufacturers();
        }
      } else {
        debugPrint('Hiba: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('API hiba: $e');
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
        if (mounted) {
          final parent =
              context.findAncestorStateOfType<GyartoParositasPageState>();
          parent?.refreshManufacturers();
        }
      } else {
        debugPrint('Hiba inaktiválásnál: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('API hiba inaktiválásnál: $e');
    }
  }

  /// Bulk create manufacturers for all selected suppliers
  Future<void> _bulkCreateSelected() async {
    // Get selected supplier maps
    final selectedSuppliers =
        suppliers.where((s) => _selectedSupplierIds.contains(s['id'])).toList();
    for (var supplier in selectedSuppliers) {
      await _createManufacturerFromSupplier(supplier);
    }
    setState(() {
      _selectedSupplierIds.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (_selectedSupplierIds.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(
              vertical: 8.0,
              horizontal: 12.0,
            ),
            child: ElevatedButton(
              onPressed: _bulkCreateSelected,
              child: Text('Kijelölt gyártók hozzáadása'),
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Szűrés beszállítói gyártóra...',
              suffixIcon: IconButton(
                icon: Icon(Icons.clear),
                onPressed: () {
                  _searchController.clear();
                  refreshList();
                },
              ),
            ),
            onChanged: (_) {
              refreshList();
            },
            onSubmitted: (_) {
              refreshList();
            },
          ),
        ),
        Expanded(
          child:
              suppliers.isEmpty && !isLoading
                  ? Center(child: Text('Nincs találat!'))
                  : ListView.builder(
                    controller: _scrollController,
                    itemCount: suppliers.length + (hasMore ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index >= suppliers.length) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: CircularProgressIndicator(),
                          ),
                        );
                      }

                      final supplier = suppliers[index];

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
                            ),
                            title: Text(
                              supplier['name'],
                              style: TextStyle(fontSize: 14),
                            ),
                          ),
                        ),
                      );

                      if (widget.isDraggable) {
                        tile = Draggable<Map<String, dynamic>>(
                          data: supplier,
                          feedback: Material(
                            child: Container(
                              padding: EdgeInsets.all(8),
                              color: Colors.grey[300],
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
