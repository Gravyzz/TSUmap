import SwiftUI

struct LoadingView: View {
    var body: some View {
        VStack() {
            Spacer()
            Text("Loading...")
                .font(Font.largeTitle)
                .fontWeight(Font.Weight.bold)
            Spacer()
            HStack {
                Spacer()
                Image("logoTSU")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 40, height: 40)
                Spacer()
                    .frame(width: 10)
                Text("MapTSU")
                    .font(Font.title)
                    .fontWeight(Font.Weight.bold)
                Spacer()
                    
            }
        }
    }
}

#Preview {
    LoadingView()
}
