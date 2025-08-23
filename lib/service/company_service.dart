import 'package:cloud_firestore/cloud_firestore.dart';

class CompanyService {
  //final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final CollectionReference _companyCollection = FirebaseFirestore.instance
      .collection('companies');

  /// ✅ Create a new company
  Future<void> createCompany(String companyId, String companyURL) async {
    try {
      await _companyCollection.add({
        'companyId': companyId,
        'companyUrl': companyURL,
        'createdAt': FieldValue.serverTimestamp(), // Auto-generate timestamp
      });
      print("✅ Company added successfully!");
    } catch (e) {
      print("❌ Error adding company: $e");
    }
  }

  /// ✅ Get all companies as a Stream (for real-time updates)
  Stream<List<Map<String, dynamic>>> getAllCompanies() {
    return _companyCollection.snapshots().map((snapshot) {
      return snapshot.docs.map((doc) {
        return {'id': doc.id, ...doc.data() as Map<String, dynamic>};
      }).toList();
    });
  }

  /// ✅ Get a single company by ID
  Future<Map<String, dynamic>?> getCompanyById(String docId) async {
    try {
      DocumentSnapshot doc = await _companyCollection.doc(docId).get();
      if (doc.exists) {
        return {'id': doc.id, ...doc.data() as Map<String, dynamic>};
      }
    } catch (e) {
      print("❌ Error fetching company: $e");
    }
    return null;
  }

  /// ✅ Get companyURL using companyId
  Future<String?> getCompanyURLByCompanyId(String companyId) async {
    try {
      QuerySnapshot querySnapshot =
          await _companyCollection
              .where('companyId', isEqualTo: companyId)
              .limit(1)
              .get();

      if (querySnapshot.docs.isNotEmpty) {
        var companyData =
            querySnapshot.docs.first.data() as Map<String, dynamic>;
        return companyData['companyUrl'] as String?;
      } else {
        print("❌ No company found with companyId: $companyId");
        return null;
      }
    } catch (e) {
      print("❌ Error fetching company URL: $e");
      return null;
    }
  }

  /// ✅ Update an existing company
  Future<void> updateCompany(
    String docId,
    String companyId,
    String companyURL,
  ) async {
    try {
      await _companyCollection.doc(docId).update({
        'companyId': companyId,
        'companyURL': companyURL,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      print("✅ Company updated successfully!");
    } catch (e) {
      print("❌ Error updating company: $e");
    }
  }

  /// ✅ Delete a company
  Future<void> deleteCompany(String docId) async {
    try {
      await _companyCollection.doc(docId).delete();
      print("✅ Company deleted successfully!");
    } catch (e) {
      print("❌ Error deleting company: $e");
    }
  }
}
