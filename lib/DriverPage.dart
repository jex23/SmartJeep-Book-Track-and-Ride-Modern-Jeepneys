import 'dart:async'; // Import for StreamSubscription
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:firebase_database/firebase_database.dart';// Import Firebase Realtime Database
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart'; // Import SharedPreferences
import 'DriverLoginPage.dart';

class DriverPage extends StatefulWidget {
  @override
  _DriverPageState createState() => _DriverPageState();
}

class _DriverPageState extends State<DriverPage> {
  String _address = "Fetching address...";
  GoogleMapController? _mapController;
  LatLng _initialPosition = LatLng(0, 0);
  MapType _currentMapType = MapType.hybrid;
  BitmapDescriptor? customIcon;
  Marker? _currentLocationMarker;

  // Initialize a list with default boolean values set to false for each seat
  List<bool> _seatSelected = List.generate(25, (index) => false);

  final DatabaseReference _databaseRef = FirebaseDatabase.instance.ref().child('Seats');

  // State variables
  bool _showSeats = false;
  bool _isExpanded = false;
  late StreamSubscription<Position> _positionStreamSubscription;
  bool _isDarkMode = false; // Variable to track dark mode status

  final DraggableScrollableController _draggableController = DraggableScrollableController();
  int _selectedIndex = 0;


  @override
  void initState() {
    super.initState();
    _loadTheme(); // Load the saved theme from SharedPreferences
    _checkPermissions();
    _loadSeatData(); // Load initial seat data from Firebase
    _loadCustomMarker();
    _startLocationUpdates(); // Start location updates
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isDarkMode = prefs.getBool('darkMode') ?? false; // Default to false if not set
    });
  }

  /////////////////////////////////////////////////////////////////

  Future<String> _getAddress(double latitude, double longitude) async {
    try {
      final placemarks = await placemarkFromCoordinates(latitude, longitude);
      final place = placemarks[0];
      return '${place.street}, ${place.subLocality}, ${place.locality}, ${place.administrativeArea}, ${place.country}';
    } catch (e) {
      print("Error getting address: $e");
      return "Unknown address";
    }
  }

  Future<void> _updateStatus(String documentId, String newStatus) async {
    try {
      await FirebaseFirestore.instance.collection('Pick_Me_Up').doc(documentId).update({
        'status': newStatus,
      });
    } catch (e) {
      print("Error updating status: $e");
    }
  }

  Future<void> _deleteDocument(String documentId) async {
    try {
      await FirebaseFirestore.instance.collection('Pick_Me_Up').doc(documentId).delete();
    } catch (e) {
      print("Error deleting document: $e");
    }
  }

  ////////////////////////////////////////////////////////////////



  ///////////////////////////////////////////////////////////////////

  Future<void> _toggleTheme() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isDarkMode = !_isDarkMode;
      prefs.setBool('darkMode', _isDarkMode);
    });
  }

  Future<void> _loadCustomMarker() async {
    customIcon = await BitmapDescriptor.fromAssetImage(
      ImageConfiguration(size: Size(45, 45)),
      'Imagess/bus2.png',
    );
  }

  Future<void> _checkPermissions() async {
    if (await Permission.location.request().isGranted) {
      _getCurrentLocation();
    } else {
      setState(() {
        _address = "Location permission denied";
      });
    }
  }

  Future<void> _getCurrentLocation() async {
    try {
      Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      setState(() {
        _initialPosition = LatLng(position.latitude, position.longitude);
      });
      _mapController?.animateCamera(CameraUpdate.newLatLng(_initialPosition));
      _getAddressFromLatLng(position);
    } catch (e) {
      setState(() {
        _address = "Error getting location";
      });
    }
  }

  Future<void> _getAddressFromLatLng(Position position) async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(position.latitude, position.longitude);
      Placemark place = placemarks[0];
      setState(() {
        _address = "${place.street ?? 'Unknown Street'}, ${place.locality ?? 'Unknown Locality'}, ${place.administrativeArea ?? 'Unknown Area'}, ${place.country ?? 'Unknown Country'}";
      });
    } catch (e) {
      setState(() {
        _address = "Error fetching address";
      });
    }
  }

  void _onMapTypeChanged(MapType mapType) {
    setState(() {
      _currentMapType = mapType;
    });
  }

  void _onSeatTapped(int index) {
    setState(() {
      _seatSelected[index] = !_seatSelected[index];
      String seatPath = 'Seat${index + 1}';
      _databaseRef.child(seatPath).set(_seatSelected[index]);
    });
  }

  Future<void> _loadSeatData() async {
    _databaseRef.onValue.listen((DatabaseEvent event) {
      final data = event.snapshot.value as Map<dynamic, dynamic>?;
      if (data != null) {
        setState(() {
          _seatSelected = List.generate(25, (index) => data['Seat${index + 1}'] ?? false);
        });
      }
    });
  }

  int get availableSeats => _seatSelected.where((selected) => !selected).length;
  int get occupiedSeats => _seatSelected.where((selected) => selected).length;

  Widget _buildMap() {
    return GoogleMap(
      initialCameraPosition: CameraPosition(
        target: _initialPosition,
        zoom: 16.0,
      ),
      mapType: _currentMapType,
      onMapCreated: (GoogleMapController controller) {
        _mapController = controller;
      },
      myLocationEnabled: true,
      myLocationButtonEnabled: true,
      markers: {
        if (_currentLocationMarker != null) _currentLocationMarker!,
      },
    );
  }

  Widget _buildPickUpList() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('Pick_Me_Up').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Center(child: CircularProgressIndicator());
        }

        final documents = snapshot.data!.docs;

        return DraggableScrollableSheet(
          expand: true,
          builder: (context, scrollController) {
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text(
                    'For Pick Up',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(width: 10),
                    Text(
                      'Available Seats: $availableSeats',
                      style: TextStyle(fontSize: 16),
                    ),
                    SizedBox(width: 10),
                    Text(
                      'Occupied Seats: $occupiedSeats',
                      style: TextStyle(fontSize: 16),
                    ),
                  ],
                ),
                Expanded(
                  child: ListView.builder(
                    controller: scrollController,
                    itemCount: documents.length,
                    itemBuilder: (context, index) {
                      final document = documents[index];
                      final documentId = document.id;
                      final fullName = document['fullName'] as String;
                      final geopoint = document['coordinates'] as GeoPoint;
                      final passengerType = document['passengerType'] as String;
                      final status = document['status'] as String;
                      final timestamp = (document['timestamp'] as Timestamp)
                          .toDate();
                      final latitude = geopoint.latitude;
                      final longitude = geopoint.longitude;

                      return FutureBuilder<String>(
                        future: _getAddress(latitude, longitude),
                        builder: (context, addressSnapshot) {
                          if (!addressSnapshot.hasData) {
                            return ListTile(
                              title: Text(fullName),
                              subtitle: Text('Fetching address...'),
                              contentPadding: EdgeInsets.all(16),
                            );
                          }

                          final address = addressSnapshot.data!;

                          return Card(
                            elevation: 5,
                            margin: EdgeInsets.symmetric(
                                vertical: 8, horizontal: 16),
                            child: ListTile(
                              contentPadding: EdgeInsets.all(16),
                              title: Text(
                                fullName,
                                style: TextStyle(
                                    fontSize: 18, fontWeight: FontWeight.bold),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Passenger Type: $passengerType',
                                    style: TextStyle(
                                        fontSize: 16, color: Colors.grey[700]),
                                  ),
                                  Text(
                                    'Status: $status',
                                    style: TextStyle(
                                        fontSize: 16, color: Colors.grey[700]),
                                  ),
                                  Text(
                                    'Address: $address',
                                    style: TextStyle(
                                        fontSize: 16, color: Colors.grey[700]),
                                  ),
                                  SizedBox(height: 8),
                                  Text(
                                    'Timestamp: ${timestamp.toLocal()}',
                                    style: TextStyle(
                                        fontSize: 16, color: Colors.grey[700]),
                                  ),
                                ],
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  TextButton(
                                    onPressed: () {
                                      _updateStatus(documentId, 'Accepted');
                                    },
                                    child: Text('Accept',
                                        style: TextStyle(color: Colors.green)),
                                  ),
                                  TextButton(
                                    onPressed: () {
                                      _updateStatus(documentId, 'Declined');
                                    },
                                    child: Text('Decline',
                                        style: TextStyle(color: Colors.red)),
                                  ),
                                  TextButton(
                                    onPressed: () {
                                      _deleteDocument(documentId);
                                    },
                                    child: Text('Delete',
                                        style: TextStyle(color: Colors.red)),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildSeats() {
    return SingleChildScrollView(
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                height: 5,
                width: 100,
                margin: EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.grey,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ],
          ),
          Text("Driver Seat", style: TextStyle(fontSize: 18)),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(width: 10),
              Text(
                'Available Seats: $availableSeats',
                style: TextStyle(fontSize: 16),
              ),
              SizedBox(width: 10),
              Text(
                'Occupied Seats: $occupiedSeats',
                style: TextStyle(fontSize: 16),
              ),
            ],
          ),
          SizedBox(height: 10),
          _buildSeatRow([0], "Driver"),
          SizedBox(height: 20),
          _buildSeatRow([1, 2, null, null, 3]),
          SizedBox(height: 20),
          _buildSeatRow([4, 5, null, null, 6]),
          SizedBox(height: 20),
          _buildSeatRow([7, 8, null, null, null, null]),
          SizedBox(height: 20),
          _buildSeatRow([9, 10, null, null, 11]),
          SizedBox(height: 20),
          _buildSeatRow([12, 13, null, null, 14]),
          SizedBox(height: 20),
          _buildSeatRow([15, 16, null, null, 17]),
          SizedBox(height: 20),
          _buildSeatRow([18, 19, null, null, 20]),
          SizedBox(height: 20),
          _buildSeatRow([21, 22, 23, 24]),
        ],
      ),
    );
  }

  Widget _buildSeatRow(List<int?> seatIndices, [String? label]) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (label != null)
          Padding(
            padding: const EdgeInsets.all(4.0),
            child: Text(label, style: TextStyle(fontSize: 16)),
          ),
        ...seatIndices.map((index) {
          if (index == null || index >= _seatSelected.length) {
            return SizedBox(width: 30); // Adjust spacing as necessary
          } else {
            return Padding(
              padding: const EdgeInsets.all(4.0),
              child: GestureDetector(
                onTap: () => _onSeatTapped(index),
                child: Container(
                  width: 50, // Adjust width as necessary
                  height: 50, // Adjust height as necessary
                  decoration: BoxDecoration(
                    color: _seatSelected[index] ? Colors.green : Colors.grey,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.black12),
                  ),
                  child: Center(
                    child: Text(
                      "Seat ${index + 1}",
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }
        }).toList(),
      ],
    );
  }

  void _expandSheet() {
    _draggableController.animateTo(
      0.6, // Adjust this value if needed to fit your design
      duration: Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _startLocationUpdates() {
    _positionStreamSubscription = Geolocator.getPositionStream(
      // Use the correct parameters based on the latest Geolocator API
    ).listen((Position position) {
      setState(() {
        _initialPosition = LatLng(position.latitude, position.longitude);
        _currentLocationMarker = Marker(
          markerId: MarkerId('currentLocation'),
          position: _initialPosition,
          icon: customIcon ?? BitmapDescriptor.defaultMarker,
        );
        _mapController?.animateCamera(CameraUpdate.newLatLng(_initialPosition));
        _getAddressFromLatLng(position);
      });

      // Send the coordinates to Firebase Realtime Database
      FirebaseDatabase.instance.ref().child('Bus/Location').set({
        'latitude': position.latitude,
        'longitude': position.longitude,
      });
    });
  }

  @override
  void dispose() {
    _positionStreamSubscription.cancel(); // Cancel location updates when not needed
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final safeAreaBottom = MediaQuery.of(context).padding.bottom;

    return MaterialApp(
      theme: _isDarkMode ? ThemeData.dark() : ThemeData.light(),
      home: Scaffold(
        appBar: AppBar(
          title: Text('Driver Page'),
          leading: Builder(
            builder: (context) => IconButton(
              icon: Icon(Icons.menu),
              onPressed: () {
                Scaffold.of(context).openDrawer();
              },
            ),
          ),
          actions: <Widget>[
            PopupMenuButton<MapType>(
              icon: Icon(Icons.map),
              onSelected: _onMapTypeChanged,
              itemBuilder: (BuildContext context) => <PopupMenuEntry<MapType>>[
                const PopupMenuItem<MapType>(
                  value: MapType.normal,
                  child: Text('Normal'),
                ),
                const PopupMenuItem<MapType>(
                  value: MapType.satellite,
                  child: Text('Satellite'),
                ),
                const PopupMenuItem<MapType>(
                  value: MapType.terrain,
                  child: Text('Terrain'),
                ),
                const PopupMenuItem<MapType>(
                  value: MapType.hybrid,
                  child: Text('Hybrid'),
                ),
              ],
            ),
            IconButton(
              icon: Icon(Icons.brightness_6),
              onPressed: () {
                _toggleTheme(); // Toggle dark mode
              },
            ),
          ],
        ),
        drawer: Drawer(
          child: ListView(
            padding: EdgeInsets.zero,
            children: <Widget>[
              DrawerHeader(
                decoration: BoxDecoration(
                  color: Colors.blue,
                ),
                child: Text(
                  'Driver Menu',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                  ),
                ),
              ),
              ListTile(
                leading: Icon(Icons.logout, color: Colors.blue), // Add the logout icon
                title: Text('Logout'),
                onTap: () {
                  // Add your logout logic here
                  Navigator.pop(context); // Close the drawer
                  _showLogoutDialog();
                },
              ),
            ],
          ),
        ),
        body: Stack(
          children: [
            _buildMap(),
            DraggableScrollableSheet(
              initialChildSize: 0.3,
              minChildSize: 0.2,
              maxChildSize: 0.6,
              controller: _draggableController,
              builder: (BuildContext context, ScrollController scrollController) {
                return GestureDetector(
                  onVerticalDragUpdate: (details) {
                    // Allow the sheet to be dragged up and down
                  },
                  onTap: () {
                    setState(() {
                      _isExpanded = !_isExpanded;
                      _draggableController.animateTo(
                        _isExpanded ? 0.6 : 0.3,
                        duration: Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                      );
                    });
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(16),
                        topRight: Radius.circular(16),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black12,
                          blurRadius: 10,
                          spreadRadius: 5,
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(
                              left: 16.0,
                              right: 16.0,
                              bottom: safeAreaBottom + 8.0,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.only(top: 8.0),
                                    child: ListView(
                                      controller: scrollController,
                                      children: [
                                        if (_showSeats) _buildSeats() else Container(),
                                        if (!_showSeats) _buildForPickUp() // Add this line to show "For Pick Up" content
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _showSeats ? 1 : 0,
          onTap: (index) {
            setState(() {
              _showSeats = index == 1; // Show seats if index is 1
              _expandSheet(); // Ensure the sheet is fully extended
            });
          },
          items: [
            BottomNavigationBarItem(
              icon: Icon(Icons.assignment_turned_in),
              label: 'For Pick Up',
              backgroundColor: Colors.blue,
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.event_seat),
              label: 'Seats',
              backgroundColor: Colors.blue,
            ),
          ],
        ),
      ),
    );
  }




  Widget _buildForPickUp() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('Pick_Me_Up').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Center(child: CircularProgressIndicator());
        }

        final documents = snapshot.data!.docs;

        return DraggableScrollableSheet(
          expand: true,
          builder: (context, scrollController) {
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text(
                    'For Pick Up',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    controller: scrollController,
                    itemCount: documents.length,
                    itemBuilder: (context, index) {
                      final document = documents[index];
                      final documentId = document.id;
                      final fullName = document['fullName'] as String;
                      final geopoint = document['coordinates'] as GeoPoint;
                      final passengerType = document['passengerType'] as String;
                      final status = document['status'] as String;
                      final timestamp = (document['timestamp'] as Timestamp).toDate();
                      final latitude = geopoint.latitude;
                      final longitude = geopoint.longitude;

                      return FutureBuilder<String>(
                        future: _getAddress(latitude, longitude),
                        builder: (context, addressSnapshot) {
                          if (!addressSnapshot.hasData) {
                            return ListTile(
                              title: Text(fullName),
                              subtitle: Text('Fetching address...'),
                              contentPadding: EdgeInsets.all(16),
                            );
                          }

                          final address = addressSnapshot.data!;

                          return Card(
                            elevation: 5,
                            margin: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                            child: ListTile(
                              contentPadding: EdgeInsets.all(16),
                              title: Text(
                                fullName,
                                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Passenger Type: $passengerType',
                                    style: TextStyle(fontSize: 16, color: Colors.grey[700]),
                                  ),
                                  Text(
                                    'Status: $status',
                                    style: TextStyle(fontSize: 16, color: Colors.grey[700]),
                                  ),
                                  Text(
                                    'Address: $address',
                                    style: TextStyle(fontSize: 16, color: Colors.grey[700]),
                                  ),
                                  SizedBox(height: 8),
                                  Text(
                                    'Timestamp: ${timestamp.toLocal()}',
                                    style: TextStyle(fontSize: 16, color: Colors.grey[700]),
                                  ),
                                ],
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  TextButton(
                                    onPressed: () {
                                      _updateStatus(documentId, 'Accepted');
                                    },
                                    child: Text('Accept', style: TextStyle(color: Colors.green)),
                                  ),
                                  TextButton(
                                    onPressed: () {
                                      _updateStatus(documentId, 'Declined');
                                    },
                                    child: Text('Decline', style: TextStyle(color: Colors.red)),
                                  ),
                                  TextButton(
                                    onPressed: () {
                                      _deleteDocument(documentId);
                                    },
                                    child: Text('Delete', style: TextStyle(color: Colors.red)),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Logout'),
          content: Text('Are you sure you want to logout?'),
          actions: <Widget>[
            TextButton(
              child: Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop(); // Close the dialog
              },
            ),
            TextButton(
              child: Text('Logout'),
              onPressed: () async {
                // Clear any necessary data or state here

                Navigator.of(context).pop(); // Close the dialog

                // Navigate to DriverLoginPage and clear the navigation stack
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (context) => DriverLoginPage()),
                      (route) => false,
                );
              },
            ),
          ],
        );
      },
    );
  }
}

void main() => runApp(MaterialApp(home: DriverPage()));
