//
//  SearchHealthProfileTool.swift
//  HealthCompanion
//
//  Created by Abhigael Mendez Carranza on 03/01/25.
//

import Foundation

/// Tool for searching the user's health profile
struct SearchHealthProfileTool: Tool {
    let name = "get_health_profile"
    let description = "Search user's health profile for relevant information to contextualize research"
    
    /// The specific type of health information to retrieve
    @Parameter(description: "Query to retrieve personal health information: Medical History, Medications, Journal Entries, etc.")
    var query: String = "Retrieve all health profile information"
    
    init() {}
    
    func execute() async throws -> (content: String, metadata: ToolMetadata?) {
        // Simulate API delay
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        
        // Create research metadata
        let metadata = ResearchMetadata(
            topic: query,
            startTime: Date().addingTimeInterval(-1200), // 20 minutes ago
            state: .processing(topic: query, startTime: Date().addingTimeInterval(-1200), sourceCount: 0),
            toolName: "get_health_profile",
            icon: "person.text.rectangle",
            colorName: "cyan"
        )
        
        // Retrieve all health profile information
        let profileInfo = retrieveHealthProfileInformation()
        
        // Generate response
        let content = """
        Health Profile Search Results for "\(query)":
        
        \(profileInfo)
        
        Note: This is simulated data. In production, this would search your actual health profile for relevant information.
        """
        
        return (content: content, metadata: metadata)
    }
    
    /// Retrieves the complete health profile information
    /// - Returns: Formatted health profile information
    private func retrieveHealthProfileInformation() -> String {
        return """
        # Health Profile Summary
        
        ## Demographics
        - **Age**: 58 years
        - **Gender**: Male
        - **Height**: 175 cm
        - **Weight**: 82 kg (BMI: 26.8)
        
        ## Active Conditions
        - **Type 2 Diabetes Mellitus** (Diagnosed: 2021-08-15)
            - Controlled with medication and diet
            - Last HbA1c: 6.8% (2023-09-10)
        - **Essential Hypertension** (Diagnosed: 2022-10-28)
            - Well-controlled with medication
            - Average BP last month: 128/82
        - **Hyperlipidemia** (Diagnosed: 2021-01-12)
            - Managed with statin therapy
            - Latest lipid panel shows improvement
        
        ## Past Conditions
        - **Acute Bronchitis** (2020-03-10 to 2020-03-30)
            - Resolved with antibiotic treatment
        - **Gastroesophageal Reflux Disease** (2019-05-20 to 2022-01-15)
            - Managed with lifestyle modifications
            - No recent symptoms reported
        
        ## Current Medications
        - **Atorvastatin** 20mg, once daily (Started: 2023-05-15)
        - **Lisinopril** 10mg, once daily (Started: 2022-11-03)
        - **Metformin** 500mg, twice daily (Started: 2021-08-22)
        - **Aspirin** 81mg, once daily (Started: 2022-01-10)
        
        ## Medication History
        - **Simvastatin** 40mg, discontinued due to muscle pain (2021-02-15 to 2023-05-14)
        - **Hydrochlorothiazide** 25mg, discontinued due to electrolyte imbalance (2020-07-10 to 2022-10-30)
        
        ## Allergies
        - **Medication Allergies**:
            - Penicillin - Severe (Rash, difficulty breathing)
            - Sulfa Drugs - Moderate (Hives, itching)
        - **Food Allergies**:
            - Shellfish - Moderate (Swelling, hives)
            - Tree Nuts - Mild (Oral itching)
        - **Environmental Allergies**:
            - Pollen - Seasonal (Spring, Fall)
            - Dust Mites - Year-round (Nasal congestion, sneezing)
        
        ## Recent Laboratory Results (2023-09-10)
        - **Glucose (fasting)**: 132 mg/dL (High)
        - **HbA1c**: 6.8% (High)
        - **Total Cholesterol**: 185 mg/dL (Normal)
        - **LDL Cholesterol**: 110 mg/dL (Above Optimal)
        - **HDL Cholesterol**: 48 mg/dL (Normal)
        - **Triglycerides**: 135 mg/dL (Normal)
        
        ## Vital Signs (Last 3 Months)
        - **Blood Pressure**: Average 128/82 mmHg
        - **Heart Rate**: Average 72 bpm
        - **Blood Glucose**: Average (Fasting) 135 mg/dL
        - **Weight**: Current 82 kg (down from 85 kg 3 months ago)
        
        ## Lifestyle
        - **Diet**: Mediterranean diet (moderate adherence)
        - **Exercise**: Walking 30 minutes daily (Average 5,200 steps/day)
        - **Smoking**: Never smoker
        - **Alcohol**: Occasional (1-2 drinks per week)
        
        ## Recent Journal Entries
        - **2023-11-15**: Felt unusually tired despite adequate sleep. Blood sugar: 142 mg/dL before dinner.
        - **2023-11-10**: Started walking 30 minutes each morning. Improved energy levels. BP: 125/80.
        - **2023-11-05**: Mild indigestion after dinner. Possibly related to new spicy food.
        - **2023-10-30**: Follow-up with Dr. Smith went well. Medication unchanged.
        """
    }
} 
