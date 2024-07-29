import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:firebase_database/firebase_database.dart';
import 'PassengerLoginPage.dart'; // Ensure this file exists and is correctly imported

class PassengerPage extends StatefulWidget {
  @override
  _PassengerPageState createState() => _PassengerPageState();
}

class _PassengerPageState extends State<PassengerPage> {
  late User currentUser;
  DocumentSnapshot? passengerSnapshot;
  Position? currentPosition;
  String? currentAddress;
  late GoogleMapController mapController;
  BitmapDescriptor? customIcon;
  int _selectedIndex = 0;
  List<bool> _seatSelected = List.generate(25, (index) => false);
  final DatabaseReference _databaseRef = FirebaseDatabase.instance.ref().child('Seats');
  MapType _currentMapType = MapType.normal; // Track map type
  StreamSubscription<Position>? _positionStreamSubscription; // Stream subscription for location updates
  Set<Marker> _markers = {}; // Set of markers for the map

  @override
  void initState() {
    super.initState();
    _requestLocationPermission();
    _loadCustomMarker();
    currentUser = FirebaseAuth.instance.currentUser!;
    FirebaseFirestore.instance.collection('passengers').doc(currentUser.uid).get().then((snapshot) {
      setState(() {
        passengerSnapshot = snapshot;
      });
    }).catchError((error) {
      print('Error retrieving user data: $error');
    });
    _loadSeatData();
  }

  @override
  void dispose() {
    _positionStreamSubscription?.cancel(); // Cancel the stream subscription when the widget is disposed
    super.dispose();
  }

  Future<void> _loadCustomMarker() async {
    customIcon = await BitmapDescriptor.fromAssetImage(
      ImageConfiguration(size: Size(1, 1)),
      'Imagess/bus2.png', // Ensure this path is correct
    );
  }

  Future<void> _requestLocationPermission() async {
    PermissionStatus status = await Permission.location.request();
    if (status.isGranted) {
      _startLocationUpdates();
    } else if (status.isDenied) {
      print('Location permission denied');
    } else if (status.isPermanentlyDenied) {
      print('Location permission permanently denied');
      openAppSettings();
    }
  }

  void _startLocationUpdates() {
    _positionStreamSubscription = Geolocator.getPositionStream(
      // Optionally use Geolocator.getPositionStream() with named parameters if supported
      // Geolocator.getPositionStream(desiredAccuracy: LocationAccuracy.high, distanceFilter: 10)
    ).listen((Position position) {
      _updateLocation(position);
    });
  }

  Future<void> _updateLocation(Position position) async {
    setState(() {
      currentPosition = position;
      _markers = {
        Marker(
          markerId: MarkerId('currentLocation'),
          position: LatLng(position.latitude, position.longitude),
          icon: customIcon ?? BitmapDescriptor.defaultMarker,
        ),
      };
    });
    _getAddressFromLatLng(position);

    if (mapController != null) {
      mapController.animateCamera(
        CameraUpdate.newLatLng(
          LatLng(position.latitude, position.longitude),
        ),
      );
    }
  }

  Future<void> _getAddressFromLatLng(Position position) async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(position.latitude, position.longitude);
      Placemark place = placemarks[0];
      setState(() {
        currentAddress = "${place.street}, ${place.locality}, ${place.postalCode}, ${place.country}";
      });
    } catch (e) {
      print('Error getting address: $e');
    }
  }

  Future<void> _refreshLocation() async {
    if (currentPosition != null) {
      await _updateLocation(currentPosition!);
    }
  }

  void _onMapCreated(GoogleMapController controller) {
    mapController = controller;
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  Future<void> _loadSeatData() async {
    _databaseRef.onValue.listen((DatabaseEvent event) {
      final data = event.snapshot.value as Map<dynamic, dynamic>?;
      if (data != null) {
        setState(() {
          _seatSelected = List.generate(25, (index) => data['Seat${index + 1}'] ?? false);
          print('Seats updated: $_seatSelected');
        });
      }
    });
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

                // Navigate to PassengerLoginPage and clear the navigation stack
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (context) => PassengerLoginPage()), // Changed to PassengerLoginPage
                      (route) => false,
                );
              },
            ),
          ],
        );
      },
    );
  }

  void _onMapTypeChanged(MapType mapType) {
    setState(() {
      _currentMapType = mapType;
    });
  }

  Widget _buildMap() {
    return currentPosition != null
        ? GoogleMap(
      onMapCreated: _onMapCreated,
      initialCameraPosition: CameraPosition(
        target: LatLng(currentPosition!.latitude, currentPosition!.longitude),
        zoom: 15.0,
      ),
      mapType: _currentMapType,
      markers: _markers, // Use the updated markers set
      myLocationEnabled: true,
      myLocationButtonEnabled: true,
      zoomControlsEnabled: true,
      zoomGesturesEnabled: true,
      scrollGesturesEnabled: true,
    )
        : Center(child: CircularProgressIndicator());
  }

  Widget _buildSeats() {
    return Center(
      child: Column(
        children: [
          Text("Seat Reservation", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          SizedBox(height: 20),
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
            return SizedBox(width: 30);
          } else {
            return Padding(
              padding: const EdgeInsets.all(4.0),
              child: Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: _seatSelected[index] ? Colors.green : Colors.grey,
                  borderRadius: BorderRadius.circular(8),
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
            );
          }
        }).toList(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final passengerSnapshot = this.passengerSnapshot; // To use in the build method

    return Scaffold(
      drawer: Drawer(
        child: ListView(
          children: <Widget>[
            DrawerHeader(
              child: Text('Passenger Menu'),
              decoration: BoxDecoration(
                color: Colors.blue,
              ),
            ),
            ListTile(
              leading: Icon(Icons.map),
              title: Text('Map'),
              onTap: () {
                Navigator.pop(context);
                _onItemTapped(0);
              },
            ),
            ListTile(
              leading: Icon(Icons.event_seat),
              title: Text('Seats'),
              onTap: () {
                Navigator.pop(context);
                _onItemTapped(1);
              },
            ),
            ListTile(
              leading: Icon(Icons.logout),
              title: Text('Logout'),
              onTap: () {
                Navigator.pop(context);
                _showLogoutDialog();
              },
            ),
          ],
        ),
      ),
      appBar: AppBar(
        title: Text('Passenger Page'),
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
        ],
      ),
      body: Stack(
        children: [
          _buildMap(),
          DraggableScrollableSheet(
            initialChildSize: 0.7,
            minChildSize: 0.1,
            maxChildSize: 1.0,
            builder: (BuildContext context, ScrollController scrollController) {
              return Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: SingleChildScrollView(
                  controller: scrollController,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      if (_selectedIndex == 0 && passengerSnapshot != null) ...[
                        Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                'Welcome!',
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blueAccent,
                                ),
                              ),
                              _buildFullNameRow(
                                passengerSnapshot!['firstName'],
                                passengerSnapshot!['middleName'],
                                passengerSnapshot!['lastName'],
                              ),
                              _buildAddressRow(passengerSnapshot!['address']),
                              _buildDetailRow('Passenger Type', passengerSnapshot!['passengerType']),
                              _buildLocationRow(),
                            ],
                          ),
                        ),
                      ],
                      if (_selectedIndex == 1) _buildSeats(),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.map),
            label: 'Map',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.event_seat),
            label: 'Seats',
          ),
        ],
        currentIndex: _selectedIndex,
        selectedItemColor: Colors.blue,
        onTap: _onItemTapped,
      ),
    );
  }

  Widget _buildFullNameRow(String firstName, String middleName, String lastName) {
    return Row(
      children: [
        Icon(Icons.person, color: Colors.blueAccent),
        SizedBox(width: 8),
        Text(
          '$firstName ${middleName.isNotEmpty ? middleName + ' ' : ''}$lastName',
          style: TextStyle(fontSize: 18),
        ),
      ],
    );
  }

  Widget _buildAddressRow(String address) {
    return Row(
      children: [
        Icon(Icons.location_on, color: Colors.blueAccent),
        SizedBox(width: 8),
        Expanded(
          child: Text(
            address,
            style: TextStyle(fontSize: 18),
          ),
        ),
      ],
    );
  }

  Widget _buildDetailRow(String title, String detail) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Icon(Icons.info, color: Colors.blueAccent),
          SizedBox(width: 8),
          Text(
            '$title: $detail',
            style: TextStyle(fontSize: 18),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationRow() {
    return Row(
      children: [
        Icon(Icons.location_searching, color: Colors.blueAccent),
        SizedBox(width: 8),
        Expanded(
          child: Text(
            currentAddress ?? 'Fetching location...',
            style: TextStyle(fontSize: 18),
          ),
        ),
        IconButton(
          icon: Icon(Icons.refresh),
          onPressed: _refreshLocation,
        ),
      ],
    );
  }
}
