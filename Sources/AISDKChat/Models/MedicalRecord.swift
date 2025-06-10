import Foundation

enum MedicalRecordType: String, Codable, CaseIterable {
    case biomarker
    case treatment
    case clinicalDocument
    case lab
    
    var displayName: String {
        switch self {
        case .biomarker: return "Biomarkers"
        case .treatment: return "Treatments"
        case .clinicalDocument: return "Clinical Documents"
        case .lab: return "Labs"
        }
    }
    
    var icon: String {
        switch self {
        case .biomarker: return "waveform.path"
        case .treatment: return "pill"
        case .clinicalDocument: return "doc.text"
        case .lab: return "testtube.2"
        }
    }
}

struct MedicalRecord: Identifiable, Codable {
    let id: String
    let name: String
    let date: Date
    let recordType: MedicalRecordType
    let summary: String
    let details: String
    
    // For mock data
    static func mockData() -> [MedicalRecord] {
        let calendar = Calendar.current
        let today = Date()
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let lastWeek = calendar.date(byAdding: .day, value: -7, to: today)!
        let lastMonth = calendar.date(byAdding: .month, value: -1, to: today)!
        
        return [
            // Biomarkers
            MedicalRecord(
                id: "bio1",
                name: "Blood Pressure",
                date: today,
                recordType: .biomarker,
                summary: "120/80 mmHg",
                details: "Systolic: 120 mmHg\nDiastolic: 80 mmHg\nPulse: 72 bpm\nPosition: Seated\nArm: Right"
            ),
            MedicalRecord(
                id: "bio2",
                name: "Blood Glucose",
                date: yesterday,
                recordType: .biomarker,
                summary: "98 mg/dL",
                details: "Fasting blood glucose measured in the morning.\nTime since last meal: 8 hours\nDevice: OneTouch Ultra"
            ),
            MedicalRecord(
                id: "bio3",
                name: "Weight",
                date: lastWeek,
                recordType: .biomarker,
                summary: "168 lbs",
                details: "Weight: 168 lbs (76.2 kg)\nBMI: 24.5\nTime: Morning\nClothing: Light clothing"
            ),
            
            // Treatments
            MedicalRecord(
                id: "treat1",
                name: "Lisinopril",
                date: today,
                recordType: .treatment,
                summary: "10mg, once daily",
                details: "Medication: Lisinopril 10mg\nFrequency: Once daily\nPurpose: Blood pressure management\nPrescribed by: Dr. Johnson\nRefills remaining: 3"
            ),
            MedicalRecord(
                id: "treat2",
                name: "Physical Therapy",
                date: lastWeek,
                recordType: .treatment,
                summary: "Lower back, 45 min session",
                details: "Treatment: Physical Therapy\nArea: Lower back\nDuration: 45 minutes\nTherapist: Sarah Williams, PT\nExercises: Core strengthening, flexibility"
            ),
            
            // Clinical Documents
            MedicalRecord(
                id: "doc1",
                name: "Annual Physical",
                date: lastMonth,
                recordType: .clinicalDocument,
                summary: "Routine check-up, all normal",
                details: "Provider: Dr. Emily Chen\nFacility: Community Health Center\nReason: Annual physical examination\nFindings: All systems normal\nRecommendations: Continue current medications, increase physical activity"
            ),
            MedicalRecord(
                id: "doc2",
                name: "Cardiology Consult",
                date: lastMonth,
                recordType: .clinicalDocument,
                summary: "Referred for mild arrhythmia",
                details: "Cardiologist: Dr. Michael Rodriguez\nReason for visit: Occasional heart palpitations\nTests performed: ECG, echocardiogram\nFindings: Mild sinus arrhythmia, structurally normal heart\nPlan: Monitor symptoms, follow up in 6 months"
            ),
            
            // Labs
            MedicalRecord(
                id: "lab1",
                name: "Complete Blood Count",
                date: lastMonth,
                recordType: .lab,
                summary: "WBC: 7.2, RBC: 4.8, Hgb: 14.2",
                details: "Test: Complete Blood Count (CBC)\nCollection date: \(lastMonth.formatted(date: .long, time: .omitted))\nResults:\n- WBC: 7.2 K/uL (Normal: 4.5-11.0)\n- RBC: 4.8 M/uL (Normal: 4.5-5.9)\n- Hemoglobin: 14.2 g/dL (Normal: 13.5-17.5)\n- Hematocrit: 42% (Normal: 41-50%)\n- Platelets: 250 K/uL (Normal: 150-450)"
            ),
            MedicalRecord(
                id: "lab2",
                name: "Lipid Panel",
                date: lastMonth,
                recordType: .lab,
                summary: "Total Cholesterol: 185 mg/dL",
                details: "Test: Lipid Panel\nCollection date: \(lastMonth.formatted(date: .long, time: .omitted))\nResults:\n- Total Cholesterol: 185 mg/dL (Desirable: <200)\n- HDL: 55 mg/dL (Good: >40)\n- LDL: 110 mg/dL (Near optimal: 100-129)\n- Triglycerides: 120 mg/dL (Normal: <150)"
            )
        ]
    }
} 