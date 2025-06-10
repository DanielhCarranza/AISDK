//
//  TestMedicalRecordsTool.swift
//  HealthCompanion
//
//  Created by Abhigael Mendez Carranza on 03/01/25.
//

import Foundation

/// Test tool for retrieving medical records and clinical notes
struct TestMedicalRecordsTool: Tool {
    let name = "get_medical_records"
    let description = "Retrieve medical records, clinical notes, and visit summaries"
    
    /// Type of medical record to retrieve
    @Parameter(description: "Type of records to retrieve", validation: ["enum": ["visit_notes", "consultations", "discharge", "all"]])
    var recordType: String = "all"
    
    /// Optional specialty filter
    @Parameter(description: "Medical specialty to filter by (leave empty for all)")
    var specialty: String = ""
    
    init() {}
    
    func execute() async throws -> (content: String, metadata: ToolMetadata?) {
        // Simulate API delay
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        
        // Create research metadata
        let metadata = ResearchMetadata(
            topic: "Medical Records: \(recordType)" + (specialty.isEmpty ? "" : " from \(specialty)"),
            startTime: Date().addingTimeInterval(-300),
            state: .processing(topic: "Medical Records Analysis", startTime: Date().addingTimeInterval(-300), sourceCount: 0),
            toolName: "get_medical_records",
            icon: "doc.text.below.ecg",
            colorName: "blue"
        )
        
        // Generate response with XML-like tags
        let content = """
        <medical_records>
            <summary>
                Medical records retrieved. Type: \(recordType)\(specialty.isEmpty ? "" : ", Specialty: \(specialty)")
            </summary>
            
            <visit_note date="2023-10-30" provider="Dr. Smith" specialty="Internal Medicine">
                <chief_complaint>Follow-up for diabetes management and medication review</chief_complaint>
                <vitals>
                    <bp>128/82 mmHg</bp>
                    <pulse>72 bpm</pulse>
                    <temp>98.6°F</temp>
                    <weight>82 kg</weight>
                </vitals>
                <assessment>
                    Patient's diabetes is currently well-controlled with medication. HbA1c has stabilized at 6.8%. 
                    Blood pressure is at target. Continuing current management plan.
                </assessment>
                <plan>
                    1. Continue Metformin 500mg BID
                    2. Continue Lisinopril 10mg daily
                    3. Maintain current diet and exercise regimen
                    4. Follow up in 3 months with repeat labs
                </plan>
            </visit_note>
            
            <visit_note date="2023-07-12" provider="Dr. Johnson" specialty="Cardiology">
                <chief_complaint>Annual cardiac evaluation</chief_complaint>
                <vitals>
                    <bp>130/84 mmHg</bp>
                    <pulse>74 bpm</pulse>
                </vitals>
                <assessment>
                    Stable coronary artery disease. Patient is asymptomatic. ECG shows normal sinus rhythm.
                    No new concerns identified.
                </assessment>
                <plan>
                    1. Continue current medications
                    2. Maintain healthy lifestyle
                    3. Routine follow-up in one year
                </plan>
            </visit_note>
            
            <consultation date="2023-08-05" provider="Dr. Williams" specialty="Endocrinology">
                <reason>Diabetes management review</reason>
                <findings>
                    Patient has been adherent to medication regimen. Blood glucose monitoring shows good control.
                    Lifestyle modifications have been beneficial. No hypoglycemic episodes reported.
                </findings>
                <recommendations>
                    Current treatment plan is appropriate. Continue monitoring. Consider CGM if insurance coverage improves.
                </recommendations>
            </consultation>
            
            <keywords>
                <keyword frequency="high">diabetes management</keyword>
                <keyword frequency="medium">hypertension</keyword>
                <keyword frequency="medium">medication adherence</keyword>
                <keyword frequency="low">dietary compliance</keyword>
            </keywords>
        </medical_records>
        """
        
        return (content: content, metadata: metadata)
    }
} 