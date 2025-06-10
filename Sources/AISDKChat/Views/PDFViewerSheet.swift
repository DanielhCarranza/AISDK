import SwiftUI
import PDFKit

struct PDFViewerSheet: View {
    let url: URL
    let title: String
    @State private var pdfData: Data?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss
    @State private var documentManager = DocumentManager()
    
    var body: some View {
        ZStack {
            if let pdfData = pdfData {
                PDFKitView2(data: pdfData)
            } else if let errorMessage = errorMessage {
                VStack {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.red)
                    
                    Text("Error loading PDF")
                        .font(.headline)
                        .padding(.top)
                    
                    Text(errorMessage)
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .padding()
                        .foregroundColor(.secondary)
                }
            } else if isLoading {
                ProgressView("Loading PDF...")
            }
            
            // Add a dismiss button in the top-right corner
            VStack {
                HStack {
                    Spacer()
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundColor(.gray)
                            .padding()
                    }
                }
                Spacer()
            }
        }
        .onAppear {
            print("🔄 PDFViewerSheet appeared")
            loadPDF()
        }
    }
    
    private func loadPDF() {
        print("🔄 Starting loadPDF for URL: \(url)")
        Task {
            do {
                print("🔍 Attempting to load PDF from: \(url)")
                
                let data: Data
                if url.isFileURL {
                    print("📂 Loading from local file")
                    data = try Data(contentsOf: url)
                } else {
                    print("🌐 Downloading from Firebase Storage")
                    
                    data = try await documentManager.loadDocument(document: Document(name: title, url: url))
                    print("📊 Data loaded successfully")
                }
                
                await MainActor.run {
                    print("✅ Setting PDF data on main thread")
                    self.pdfData = data
                    isLoading = false
                }
            } catch {
                print("❌ Error loading PDF: \(error.localizedDescription)")
                await MainActor.run {
                    isLoading = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

struct PDFKitView2: UIViewRepresentable {
    let data: Data

    func makeUIView(context: Context) -> PDFView {
        print("📱 Creating PDFView")
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePage
        pdfView.displayDirection = .vertical
        
        // Enable page navigation
        pdfView.usePageViewController(true)
        
        // Add zoom support
        pdfView.minScaleFactor = pdfView.scaleFactorForSizeToFit
        pdfView.maxScaleFactor = 4.0
        
        return pdfView
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        print("🔄 Updating PDFView with data (\(data.count) bytes)")
        if let document = PDFDocument(data: data) {
            print("✅ Created PDF document with \(document.pageCount) pages")
            uiView.document = document
        } else {
            print("❌ Failed to create PDF document from data")
        }
    }
}

