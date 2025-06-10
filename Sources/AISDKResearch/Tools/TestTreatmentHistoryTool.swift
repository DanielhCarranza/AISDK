//
//  TestTreatmentHistoryTool.swift
//  HealthCompanion
//
//  Created by Abhigael Mendez Carranza on 03/01/25.
//

import Foundation

/// Test tool for retrieving treatment history
struct TestTreatmentHistoryTool: Tool {
    let name = "get_treatment_history"
    let description = "Retrieve history of medications, therapies, and procedures"
    
    /// Type of treatment history to retrieve
    @Parameter(description: "Type of treatment to retrieve", validation: ["enum": ["medications", "procedures", "therapies", "all"]])
    var treatmentType: String = "all"
    
    /// Status filter
    @Parameter(description: "Treatment status", validation: ["enum": ["current", "past", "all"]])
    var status: String = "all"
    
    init() {}
    
    func execute() async throws -> (content: String, metadata: ToolMetadata?) {
        // Simulate API delay
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        
        // Create research metadata
        let metadata = ResearchMetadata(
            topic: "Treatment History: \(treatmentType) (\(status))",
            startTime: Date().addingTimeInterval(-300),
            state: .processing(topic: "Treatment History Analysis", startTime: Date().addingTimeInterval(-300), sourceCount: 0),
            toolName: "get_treatment_history",
            icon: "pill",
            colorName: "orange"
        )
        
        // Generate response with XML-like tags
        let content = """
        <treatment_history>
            <summary>
                Treatment history retrieved. Type: \(treatmentType), Status: \(status)
            </summary>
            
            <current_medications>
                <medication name="Atorvastatin" dose="20mg" frequency="once daily" started="2023-05-15">
                    <class>HMG-CoA Reductase Inhibitor (Statin)</class>
                    <indication>Hyperlipidemia</indication>
                    <prescriber>Dr. Smith, Internal Medicine</prescriber>
                    <notes>Tolerated well. No reported muscle pain.</notes>
                </medication>
                
                <medication name="Lisinopril" dose="10mg" frequency="once daily" started="2022-11-03">
                    <class>ACE Inhibitor</class>
                    <indication>Hypertension</indication>
                    <prescriber>Dr. Smith, Internal Medicine</prescriber>
                    <notes>Effective control of blood pressure. No cough reported.</notes>
                </medication>
                
                <medication name="Metformin" dose="500mg" frequency="twice daily" started="2021-08-22">
                    <class>Biguanide</class>
                    <indication>Type 2 Diabetes</indication>
                    <prescriber>Dr. Smith, Internal Medicine</prescriber>
                    <notes>Initially had mild GI discomfort which resolved.</notes>
                </medication>
                
                <medication name="Aspirin" dose="81mg" frequency="once daily" started="2022-01-10">
                    <class>Antiplatelet</class>
                    <indication>Cardiovascular risk reduction</indication>
                    <prescriber>Dr. Johnson, Cardiology</prescriber>
                    <notes>Enteric-coated to reduce GI irritation.</notes>
                </medication>
            </current_medications>
            
            <past_medications>
                <medication name="Simvastatin" dose="40mg" frequency="once daily" started="2021-02-15" ended="2023-05-14">
                    <class>HMG-CoA Reductase Inhibitor (Statin)</class>
                    <indication>Hyperlipidemia</indication>
                    <reason_discontinued>Muscle pain (myalgia)</reason_discontinued>
                    <notes>Effectiveness was acceptable but side effects led to switch.</notes>
                </medication>
                
                <medication name="Hydrochlorothiazide" dose="25mg" frequency="once daily" started="2020-07-10" ended="2022-10-30">
                    <class>Thiazide Diuretic</class>
                    <indication>Hypertension</indication>
                    <reason_discontinued>Electrolyte imbalance (hypokalemia)</reason_discontinued>
                    <notes>Effective for BP but required potassium supplementation.</notes>
                </medication>
            </past_medications>
            
            <procedures>
                <procedure name="Colonoscopy" date="2022-04-15">
                    <provider>Dr. Roberts, Gastroenterology</provider>
                    <indication>Routine screening</indication>
                    <findings>Normal, no polyps identified</findings>
                    <follow_up>Repeat in 10 years</follow_up>
                </procedure>
                
                <procedure name="Cardiac Stress Test" date="2023-07-12">
                    <provider>Dr. Johnson, Cardiology</provider>
                    <indication>Annual cardiac evaluation</indication>
                    <findings>Normal exercise capacity. No evidence of ischemia.</findings>
                    <follow_up>Routine cardiology follow-up in one year</follow_up>
                </procedure>
            </procedures>
            
            <therapies>
                <therapy name="Physical Therapy" started="2020-02-10" ended="2020-05-15">
                    <indication>Knee rehabilitation post-arthroscopy</indication>
                    <provider>Capital Physical Therapy</provider>
                    <frequency>Twice weekly</frequency>
                    <outcome>Complete functional recovery</outcome>
                </therapy>
                
                <therapy name="Nutritional Counseling" started="2021-09-05" ended="2022-03-20">
                    <indication>Diabetes management</indication>
                    <provider>Lisa Johnson, RD</provider>
                    <frequency>Monthly</frequency>
                    <outcome>Improved dietary patterns, weight loss of 3kg</outcome>
                </therapy>
            </therapies>
            
            <adherence>
                <summary>Overall medication adherence rate: 92%</summary>
                <medication name="Metformin" adherence="95%" note="Occasionally misses evening dose" />
                <medication name="Atorvastatin" adherence="98%" note="High adherence" />
                <medication name="Lisinopril" adherence="97%" note="High adherence" />
                <medication name="Aspirin" adherence="90%" note="Sometimes forgets on weekends" />
            </adherence>
        </treatment_history>
        """
        
        return (content: content, metadata: metadata)
    }
} 