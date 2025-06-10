//
//  TestMedicalHistoryTool.swift
//  HealthCompanion
//
//  Created by Abhigael Mendez Carranza on 03/01/25.
//

import Foundation

/// Test tool for retrieving medical history and conditions
struct TestMedicalHistoryTool: Tool {
    let name = "get_medical_history"
    let description = "Retrieve comprehensive medical history including conditions, diagnoses, and surgeries"
    
    /// Type of medical history to retrieve
    @Parameter(description: "Type of history to retrieve", validation: ["enum": ["conditions", "surgeries", "family", "all"]])
    var historyType: String = "all"
    
    /// Optional system filter (cardiovascular, respiratory, etc.)
    @Parameter(description: "Body system to filter by (leave empty for all)")
    var bodySystem: String = ""
    
    init() {}
    
    func execute() async throws -> (content: String, metadata: ToolMetadata?) {
        // Simulate API delay
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        
        // Create research metadata
        let metadata = ResearchMetadata(
            topic: "Medical History: \(historyType)" + (bodySystem.isEmpty ? "" : " (\(bodySystem) system)"),
            startTime: Date().addingTimeInterval(-300),
            state: .processing(topic: "Medical History Analysis", startTime: Date().addingTimeInterval(-300), sourceCount: 0),
            toolName: "get_medical_history",
            icon: "list.clipboard.fill",
            colorName: "indigo"
        )
        
        // Generate response with XML-like tags
        let content = """
        <medical_history>
            <summary>
                Medical history retrieved. Type: \(historyType)\(bodySystem.isEmpty ? "" : ", System: \(bodySystem)")
            </summary>
            
            <active_conditions>
                <condition name="Type 2 Diabetes Mellitus" onset="2021-08-15">
                    <status>Controlled with medication and diet</status>
                    <treatment>Metformin 500mg BID</treatment>
                    <last_assessment date="2023-09-10">HbA1c: 6.8%</last_assessment>
                    <severity>Moderate</severity>
                    <notes>Diagnosis followed 3 years of prediabetes. No end-organ damage identified.</notes>
                </condition>
                
                <condition name="Essential Hypertension" onset="2022-10-28">
                    <status>Well-controlled with medication</status>
                    <treatment>Lisinopril 10mg daily</treatment>
                    <last_assessment date="2023-10-30">BP: 128/82 mmHg</last_assessment>
                    <severity>Mild</severity>
                    <notes>No evidence of hypertensive heart disease. Annual cardiac evaluation normal.</notes>
                </condition>
                
                <condition name="Hyperlipidemia" onset="2021-01-12">
                    <status>Managed with statin therapy</status>
                    <treatment>Atorvastatin 20mg daily</treatment>
                    <last_assessment date="2023-09-10">LDL: 110 mg/dL</last_assessment>
                    <severity>Mild</severity>
                    <notes>Previously on Simvastatin, switched due to muscle pain.</notes>
                </condition>
            </active_conditions>
            
            <past_conditions>
                <condition name="Acute Bronchitis" onset="2020-03-10" resolved="2020-03-30">
                    <treatment>Azithromycin 5-day course</treatment>
                    <severity>Moderate</severity>
                    <notes>Full resolution without complications.</notes>
                </condition>
                
                <condition name="Gastroesophageal Reflux Disease" onset="2019-05-20" resolved="2022-01-15">
                    <treatment>Lifestyle modifications, Omeprazole PRN</treatment>
                    <severity>Mild</severity>
                    <notes>Managed with dietary changes and weight management. No recent symptoms.</notes>
                </condition>
            </past_conditions>
            
            <surgical_history>
                <procedure name="Appendectomy" date="1998-06-12">
                    <type>Open surgery</type>
                    <complication>None</complication>
                    <notes>Uncomplicated recovery.</notes>
                </procedure>
                
                <procedure name="Right Knee Arthroscopy" date="2015-09-03">
                    <type>Minimally invasive</type>
                    <indication>Meniscus tear</indication>
                    <complication>None</complication>
                    <notes>Complete recovery with physical therapy.</notes>
                </procedure>
            </surgical_history>
            
            <family_history>
                <relative type="Father">
                    <condition name="Type 2 Diabetes" onset_age="52" />
                    <condition name="Myocardial Infarction" onset_age="68" />
                </relative>
                
                <relative type="Mother">
                    <condition name="Hypertension" onset_age="60" />
                    <condition name="Osteoarthritis" onset_age="65" />
                </relative>
                
                <relative type="Paternal Grandfather">
                    <condition name="Stroke" onset_age="71" />
                </relative>
            </family_history>
            
            <risk_factors>
                <risk factor="Family history of diabetes" level="High" />
                <risk factor="Previous sedentary lifestyle" level="Moderate" />
                <risk factor="BMI history" level="Moderate" note="Peak BMI 29.2 in 2020, current 26.8" />
            </risk_factors>
        </medical_history>
        """
        
        return (content: content, metadata: metadata)
    }
} 