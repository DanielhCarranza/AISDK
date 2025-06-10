//
//  TestLabResultsTool.swift
//  HealthCompanion
//
//  Created by Abhigael Mendez Carranza on 03/01/25.
//

import Foundation

/// Test tool for retrieving laboratory and imaging results
struct TestLabResultsTool: Tool {
    let name = "get_lab_results"
    let description = "Retrieve laboratory test results and imaging reports"
    
    /// Type of lab results to retrieve
    @Parameter(description: "Type of results to retrieve", validation: ["enum": ["blood", "imaging", "pathology", "all"]])
    var resultType: String = "all"
    
    /// Time period to search
    @Parameter(description: "Time period for results", validation: ["enum": ["recent", "6months", "year", "all"]])
    var timeframe: String = "recent"
    
    init() {}
    
    func execute() async throws -> (content: String, metadata: ToolMetadata?) {
        // Simulate API delay
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        
        // Create research metadata
        let metadata = ResearchMetadata(
            topic: "Lab Results: \(resultType) from \(timeframe) timeframe",
            startTime: Date().addingTimeInterval(-300),
            state: .processing(topic: "Lab Data Analysis", startTime: Date().addingTimeInterval(-300), sourceCount: 0),
            toolName: "get_lab_results",
            icon: "cross.case",
            colorName: "purple"
        )
        
        // Generate response with XML-like tags
        let content = """
        <lab_results>
            <summary>
                Laboratory results for \(timeframe) period. Type: \(resultType)
            </summary>
            
            <blood_tests>
                <test date="2023-09-10" name="Complete Blood Count (CBC)">
                    <result name="WBC" value="6.8" unit="x10^9/L" range="4.5-11.0" status="normal" />
                    <result name="RBC" value="4.92" unit="x10^12/L" range="4.2-5.8" status="normal" />
                    <result name="Hemoglobin" value="14.2" unit="g/dL" range="13.5-17.5" status="normal" />
                    <result name="Hematocrit" value="42" unit="%" range="41-50" status="normal" />
                    <result name="Platelets" value="250" unit="x10^9/L" range="150-450" status="normal" />
                </test>
                
                <test date="2023-09-10" name="Lipid Panel">
                    <result name="Total Cholesterol" value="185" unit="mg/dL" range="<200" status="normal" />
                    <result name="LDL" value="110" unit="mg/dL" range="<100" status="borderline" />
                    <result name="HDL" value="48" unit="mg/dL" range=">40" status="normal" />
                    <result name="Triglycerides" value="135" unit="mg/dL" range="<150" status="normal" />
                </test>
                
                <test date="2023-09-10" name="Glucose Panel">
                    <result name="Fasting Glucose" value="132" unit="mg/dL" range="70-100" status="high" />
                    <result name="HbA1c" value="6.8" unit="%" range="<5.7" status="high" />
                    <result name="Insulin" value="12.4" unit="uIU/mL" range="2.6-24.9" status="normal" />
                </test>
            </blood_tests>
            
            <imaging>
                <report date="2023-07-15" type="Chest X-Ray">
                    <finding>No acute cardiopulmonary process identified. Heart size is normal. Lungs are clear.</finding>
                    <impression>Normal chest radiograph.</impression>
                </report>
                
                <report date="2023-05-22" type="Abdominal Ultrasound">
                    <finding>Liver normal in size with homogeneous echotexture. No focal lesions identified. Gallbladder, spleen, and kidneys appear normal.</finding>
                    <impression>Unremarkable abdominal ultrasound.</impression>
                </report>
            </imaging>
            
            <trends>
                <trend parameter="Glucose">Showing consistently elevated levels over the past year</trend>
                <trend parameter="LDL">Moderate improvement following statin therapy</trend>
                <trend parameter="HbA1c">Stabilized around 6.8% for the past 6 months</trend>
            </trends>
        </lab_results>
        """
        
        return (content: content, metadata: metadata)
    }
} 