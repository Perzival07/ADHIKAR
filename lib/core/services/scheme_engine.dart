import '../models/citizen_profile.dart';
import '../models/scheme_model.dart';
import '../../data/schemes_corpus.dart';

class SchemeEngine {
  /// Evaluates and ranks schemes tailored to the citizen profile
  static List<SchemeModel> evaluate(CitizenProfile profile) {
    final allSchemes = SchemesCorpus.getSchemes();
    final List<SchemeModel> results = [];

    // The corpus is cached and shared, so clear results from any previous run.
    for (final s in allSchemes) {
      s.matchConfidence = 1.0;
      s.generatedReason = null;
      s.generatedReasonHi = null;
    }

    for (var scheme in allSchemes) {
      double score = 0.0;
      String reasonEn = '';
      String reasonHi = '';

      switch (scheme.id) {
        case 'pm_kisan':
          if (profile.isFarmer && profile.landHoldingAcres > 0) {
            score = 1.0;
            reasonEn = 'You qualify because you own ${profile.landHoldingAcres} acres of agricultural land in ${profile.state} and actively practice farming.';
            reasonHi = 'आप पात्र हैं क्योंकि आपके पास ${profile.state} में ${profile.landHoldingAcres} एकड़ कृषि भूमि है और आप खेती करते हैं।';
          } else if (profile.isFarmer && profile.landHoldingAcres == 0) {
            score = 0.4; // Landless farmer warning
            reasonEn = 'PM-KISAN strictly requires land ownership records (Khatauni) in your name. Since you marked land as 0, verify tenancy status at your Tehsil.';
            reasonHi = 'पीएम-किसान के लिए आपके नाम पर खतौनी होना अनिवार्य है। यदि भूमिहीन हैं, तो तहसील से बटाईदार नियमों की पुष्टि करें।';
          }
          break;

        case 'ayushman_bharat':
          if (profile.age >= 70) {
            score = 1.0;
            reasonEn = 'You qualify universally because you are ${profile.age} years old (Senior Citizens 70+ receive universal ₹5 Lakh cover regardless of income).';
            reasonHi = 'आप पात्र हैं क्योंकि आपकी आयु ${profile.age} वर्ष है (70+ आयु के सभी वरिष्ठ नागरिकों को आय सीमा के बिना ₹5 लाख का कवर मिलता है)।';
          } else if (profile.hasBplOrAay || profile.isLowIncome) {
            score = 1.0;
            reasonEn = 'You qualify because your household holds a ${profile.rationCard} card with annual income in the ${profile.annualIncomeRange} bracket.';
            reasonHi = 'आप पात्र हैं क्योंकि आपके पास ${profile.rationCard} राशन कार्ड है और पारिवारिक आय ${profile.annualIncomeRange} श्रेणी में है।';
          } else if (profile.socialCategory == 'SC' || profile.socialCategory == 'ST') {
            score = 0.85;
            reasonEn = 'High priority under SECC social category inclusion for ${profile.socialCategory} families.';
            reasonHi = 'सामाजिक आर्थिक गणना (SECC) में ${profile.socialCategory} वर्ग के तहत उच्च प्राथमिकता।';
          }
          break;

        case 'pm_awas_gramin':
          if (profile.hasBplOrAay && profile.isLowIncome) {
            score = 0.95;
            reasonEn = 'You qualify as an economically vulnerable rural household (${profile.rationCard}) eligible for pucca housing grant under Awas+.';
            reasonHi = 'आप आर्थिक रूप से कमजोर परिवार (${profile.rationCard}) के रूप में पक्के मकान के अनुदान के पात्र हैं।';
          }
          break;

        case 'pm_ujjwala':
          if (profile.gender == 'Female' && profile.age >= 18 && (profile.hasBplOrAay || profile.socialCategory == 'SC' || profile.socialCategory == 'ST' || profile.socialCategory == 'OBC')) {
            score = 1.0;
            reasonEn = 'You qualify as an adult woman (${profile.age} years) from an eligible ${profile.socialCategory} household without active LPG.';
            reasonHi = 'आप पात्र ${profile.socialCategory} परिवार की वयस्क महिला (${profile.age} वर्ष) के रूप में मुफ्त गैस कनेक्शन हेतु पात्र हैं।';
          } else if (profile.gender == 'Male' && (profile.hasBplOrAay || profile.isLowIncome)) {
            score = 0.8;
            reasonEn = 'Note: Ujjwala connections are issued in the name of the adult female head of the household. Apply with the adult woman member of your family.';
            reasonHi = 'ध्यान दें: उज्ज्वला कनेक्शन परिवार की वयस्क महिला के नाम पर जारी होता है। घर की महिला सदस्य के नाम से आवेदन करें।';
          }
          break;

        case 'pm_vishwakarma':
          if (profile.isArtisan && profile.age >= 18) {
            score = 1.0;
            final trade = profile.artisanTrade.isNotEmpty ? profile.artisanTrade : 'traditional craftsperson';
            reasonEn = 'You qualify as a practicing artisan ($trade) working with hand tools in ${profile.state}.';
            reasonHi = 'आप ${profile.state} में हाथ और औजारों से काम करने वाले कुशल कारीगर ($trade) के रूप में पात्र हैं।';
          }
          break;

        case 'pm_svanidhi':
          if (profile.isStreetVendor && profile.age >= 18) {
            score = 1.0;
            reasonEn = 'You qualify as an urban/peri-urban street vendor eligible for micro-credit working capital starting at ₹10,000.';
            reasonHi = 'आप रेहड़ी-पटरी विक्रेता के रूप में ₹10,000 के पहले चरण के कार्यशील पूंजी ऋण के लिए सीधे पात्र हैं।';
          }
          break;

        case 'atal_pension':
          if (profile.age >= 18 && profile.age <= 40 && profile.occupation != 'Salaried') {
            score = 1.0;
            reasonEn = 'You qualify because you are ${profile.age} years old (eligible entry 18-40) and work in the unorganized sector without paying income tax.';
            reasonHi = 'आप पात्र हैं क्योंकि आपकी आयु ${profile.age} वर्ष (प्रवेश आयु 18-40) है और आप असंगठित क्षेत्र में कार्य करते हैं।';
          }
          break;

        case 'sukanya_samriddhi':
          if (profile.hasGirlChildUnder10) {
            score = 1.0;
            reasonEn = 'You qualify as the parent/guardian of a girl child under 10 years of age for high-interest (8.2%) sovereign savings.';
            reasonHi = 'आप 10 वर्ष से कम आयु की बेटी के अभिभावक के रूप में 8.2% की उच्चतम ब्याज वाली बचत योजना के पात्र हैं।';
          }
          break;

        case 'nsap_old_age_pension':
          if (profile.age >= 60 && profile.hasBplOrAay) {
            score = 1.0;
            reasonEn = 'You qualify as a senior citizen aged ${profile.age} from an economically deprived (${profile.rationCard}) family.';
            reasonHi = 'आप ${profile.rationCard} परिवार के ${profile.age} वर्षीय वरिष्ठ नागरिक के रूप में मासिक वृद्धावस्था पेंशन के पात्र हैं।';
          }
          break;

        case 'nsap_widow_pension':
          if (profile.isWidow && profile.age >= 40 && (profile.hasBplOrAay || profile.isLowIncome)) {
            score = 1.0;
            reasonEn = 'You qualify as a widowed woman aged ${profile.age} years (criteria: 40-79 yrs) from an economically vulnerable background.';
            reasonHi = 'आप 40 से 79 वर्ष की आयु वर्ग की विधवा महिला (${profile.age} वर्ष) के रूप में विधवा पेंशन हेतु पात्र हैं।';
          }
          break;

        case 'nsap_disability_pension':
          if (profile.isDivyangjan && profile.age >= 18 && (profile.hasBplOrAay || profile.isLowIncome)) {
            score = 1.0;
            reasonEn = 'You qualify because you have certified disability (40%+) and belong to an economically vulnerable household.';
            reasonHi = 'आप प्रमाणित दिव्यांगता (40%+) और आर्थिक रूप से कमजोर पृष्ठभूमि के कारण दिव्यांग पेंशन के पात्र हैं।';
          }
          break;

        case 'post_matric_scholarship':
          if (profile.isStudent && (profile.socialCategory == 'SC' || profile.socialCategory == 'ST' || profile.socialCategory == 'OBC') && profile.isLowIncome) {
            score = 1.0;
            reasonEn = 'You qualify as a ${profile.socialCategory} student pursuing ${profile.studentLevel} with annual family income under ₹2.5 Lakh.';
            reasonHi = 'आप ${profile.studentLevel} की पढ़ाई कर रहे ${profile.socialCategory} छात्र हैं और पारिवारिक आय ₹2.5 लाख से कम है।';
          }
          break;

        case 'mgnrega':
          if (profile.age >= 18 && profile.occupation != 'Salaried') {
            score = 0.95;
            reasonEn = 'You are entitled to 100 days of legally guaranteed rural employment and wage protection in your Gram Panchayat.';
            reasonHi = 'आप अपनी ग्राम पंचायत में 100 दिन के वैधानिक गारंटीशुदा रोजगार और मजदूरी के कानूनी हकदार हैं।';
          }
          break;

        case 'pm_matru_vandana':
          if (profile.gender == 'Female' && profile.age >= 19 && (profile.hasBplOrAay || profile.socialCategory == 'SC' || profile.socialCategory == 'ST' || profile.isLowIncome)) {
            score = 0.9;
            reasonEn = 'You qualify for maternity financial assistance (₹5,000 - ₹6,000) during pregnancy and post-natal care.';
            reasonHi = 'आप गर्भावस्था और प्रसव के दौरान ₹5,000 से ₹6,000 की मातृत्व आर्थिक सहायता की पात्र हैं।';
          }
          break;

        case 'pm_suraksha_bima':
          if (profile.age >= 18 && profile.age <= 70) {
            score = 1.0;
            reasonEn = 'You qualify as an adult citizen aged ${profile.age} holding a bank account to get ₹2 Lakh accident protection for just ₹20/year.';
            reasonHi = 'आप ${profile.age} वर्ष की आयु के बैंक खाताधारक के रूप में मात्र ₹20/वर्ष में ₹2 लाख के दुर्घटना बीमा के पात्र हैं।';
          }
          break;

        // --- State Specific Evaluation Rules ---
        case 'up_kanya_sumangala':
          if (profile.state == 'Uttar Pradesh' && (profile.hasGirlChildUnder10 || (profile.gender == 'Female' && profile.age <= 22)) && profile.isLowIncome) {
            score = 1.0;
            reasonEn = 'You qualify as an Uttar Pradesh resident for ₹25,000 cash milestones for girl child education and welfare.';
            reasonHi = 'आप उत्तर प्रदेश निवासी के रूप में बालिका शिक्षा व कल्याण हेतु ₹25,000 सहायता के पात्र हैं।';
          }
          break;

        case 'up_abhyudaya':
          if (profile.state == 'Uttar Pradesh' && (profile.isStudent || (profile.age >= 17 && profile.age <= 35))) {
            score = 1.0;
            reasonEn = 'You qualify as an Uttar Pradesh student/youth eligible for free competitive exam coaching (UPSC/UPPSC/JEE/NEET) & tablets.';
            reasonHi = 'आप उत्तर प्रदेश के छात्र/युवा के रूप में मुफ्त प्रतियोगी कोचिंग एवं टैबलेट सहायता के पात्र हैं।';
          }
          break;

        case 'mh_ladki_bahin':
          if (profile.state == 'Maharashtra' && profile.gender == 'Female' && profile.age >= 21 && profile.age <= 65 && (profile.isLowIncome || profile.hasBplOrAay)) {
            score = 1.0;
            reasonEn = 'You qualify as a woman aged ${profile.age} residing in Maharashtra with family income under ₹2.5 Lakh for ₹1,500/month DBT.';
            reasonHi = 'तुम्ही महाराष्ट्रातील महिला (वय ${profile.age} वर्षे) म्हणून दरमहा ₹१,५०० थेट अनुदानासाठी पात्र आहात.';
          }
          break;

        case 'mh_namo_shetkari':
          if (profile.state == 'Maharashtra' && profile.isFarmer && profile.landHoldingAcres > 0) {
            score = 1.0;
            reasonEn = 'You qualify as a landholding farmer in Maharashtra to receive an additional ₹6,000/yr over PM-KISAN (total ₹12,000/yr).';
            reasonHi = 'तुम्ही महाराष्ट्रातील शेतकरी म्हणून पीएम-किसान व्यतिरिक्त अतिरिक्त ₹६,००० (एकूण ₹१२,०००) मदतीस पात्र आहात.';
          }
          break;

        case 'mp_ladli_behna':
          if (profile.state == 'Madhya Pradesh' && profile.gender == 'Female' && profile.age >= 21 && profile.age <= 60 && (profile.isLowIncome || profile.hasBplOrAay)) {
            score = 1.0;
            reasonEn = 'You qualify as a woman aged ${profile.age} in Madhya Pradesh for direct ₹1,250/month DBT under Ladli Behna Yojana.';
            reasonHi = 'आप मध्य प्रदेश में ₹1,250 प्रतिमाह लाड़ली बहना सहायता राशि प्राप्त करने हेतु पात्र हैं।';
          }
          break;

        case 'bihar_kanya_utthan':
          if (profile.state == 'Bihar' && (profile.gender == 'Female' && (profile.isStudent || profile.age <= 28))) {
            score = 1.0;
            reasonEn = 'You qualify as a female student in Bihar for up to ₹50,000 graduation incentive or ₹25,000 intermediate incentive.';
            reasonHi = 'आप बिहार की छात्रा के रूप में स्नातक उत्तीर्ण पर ₹50,000 या 12वीं उत्तीर्ण पर ₹25,000 प्रोत्साहन राशि की पात्र हैं।';
          }
          break;

        case 'wb_annapurna_bhandar':
          if (profile.state == 'West Bengal' && profile.gender == 'Female') {
            if (profile.age >= 25 && profile.age <= 60 && profile.occupation != 'Salaried') {
              score = 1.0;
              reasonEn = 'You qualify as a female resident of West Bengal aged ${profile.age} for ₹3,000/month DBT direct financial assistance and 100% free state bus travel.';
              reasonHi = 'আপনি পশ্চিমবঙ্গের ২৫-৬০ বছর বয়সী মহিলা হিসেবে প্রতি মাসে ₹৩,০০০ ডিবিটি অনুদান ও বিনামূল্যে সরকারি বাসে সফরের যোগ্য।';
            } else if (profile.age < 25) {
              score = 0.4;
              reasonEn = 'Annapurna Bhandar requires minimum age of 25 (your age: ${profile.age}). For women aged 21, you qualify for Banglar Yuva Sathi (₹1,500/mo), Bhagini Nivedita (₹50,000 grant), and Yuva Shakti.';
              reasonHi = 'অন্নপূর্ণা ভাণ্ডারের জন্য সর্বনিম্ন বয়স ২৫ বছর। ২১ বছর বয়সী নারী হিসেবে আপনি যুব সাথী ও ভগিনী নিবেদিতা প্রকল্পের যোগ্য।';
            }
          }
          break;

        case 'wb_banglar_yuva_sathi':
          if (profile.state == 'West Bengal' && profile.age >= 21 && profile.age <= 40 && profile.occupation != 'Salaried') {
            score = 1.0;
            reasonEn = 'You qualify as a permanent resident of West Bengal aged ${profile.age} (criteria: 21-40 years, min 10th pass) for ₹1,500/month DBT unemployment assistance for up to 5 years.';
            reasonHi = 'আপনি পশ্চিমবঙ্গের ২১ থেকে ৪০ বছর বয়সী বাসিন্দা হিসেবে ৫ বছর পর্যন্ত প্রতি মাসে ₹১,৫০০ যুব সাথী বেকার ভাতার যোগ্য।';
          }
          break;

        case 'wb_bhagini_nivedita':
          if (profile.state == 'West Bengal' && profile.gender == 'Female' && (profile.isStudent || (profile.age >= 17 && profile.age <= 25))) {
            score = 1.0;
            reasonEn = 'You qualify as an unmarried woman in West Bengal pursuing higher education for ₹50,000 total study grant (₹17,000 in Year 1, ₹17,000 in Year 2, and ₹16,000 in Year 3).';
            reasonHi = 'আপনি পশ্চিমবঙ্গের কলেজে পাঠরত অবিবাহিত ছাত্রী হিসেবে মোট ₹৫০,০০০ (১৭,০০০ + ১৭,০০০ + ১৬,০০০) উচ্চশিক্ষা অনুদানের যোগ্য।';
          }
          break;

        case 'wb_yuva_shakti':
          if (profile.state == 'West Bengal' && profile.age >= 21 && profile.age <= 45 && (profile.isLowIncome || profile.hasBplOrAay || profile.annualIncomeRange == '< 1 Lakh') && profile.occupation != 'Salaried') {
            score = 1.0;
            reasonEn = 'You qualify as an eligible unemployed youth in West Bengal aged ${profile.age} with family income under ₹1 Lakh for ₹2,000 - ₹3,000 monthly allowance under Yuva Shakti Bharosa Card.';
            reasonHi = 'আপনি পশ্চিমবঙ্গের ২১-৪৫ বছর বয়সী যুবক/মহিলা হিসেবে প্রতি মাসে ₹২,০০০ থেকে ₹৩,০০০ যুব শক্তি ভাতার যোগ্য।';
          }
          break;

        case 'wb_lakshmir_bhandar':
          // Superseded / expired scheme
          score = 0.0;
          break;

        case 'gj_vhali_dikri':
          if (profile.state == 'Gujarat' && (profile.hasGirlChildUnder10 || (profile.gender == 'Female' && profile.age <= 18)) && profile.isLowIncome) {
            score = 1.0;
            reasonEn = 'You qualify in Gujarat for ₹1,10,000 total financial assistance for your daughter\'s education and future.';
            reasonHi = 'તમે ગુજરાતમાં દીકરીના શિક્ષણ અને ભવિષ્ય માટે કુલ ₹૧,૧૦,૦૦૦ ની સહાય માટે પાત્ર છો.';
          }
          break;

        case 'rj_maa_ayushman':
        case 'rj_chiranjeevi':
          if (profile.state == 'Rajasthan') {
            score = 1.0;
            reasonEn = 'You qualify as a resident of Rajasthan for universal cashless healthcare treatment up to ₹25 Lakh under Mukhyamantri Ayushman Arogya (MAA) Yojana.';
            reasonHi = 'आप राजस्थान के निवासी के रूप में मुख्यमंत्री आयुष्मान आरोग्य (माँ) योजना के तहत ₹25 लाख तक के कैशलेस इलाज के पात्र हैं।';
          }
          break;

        case 'or_subhadra':
          if (profile.state == 'Odisha' && profile.gender == 'Female' && profile.age >= 21 && profile.age <= 60 && (profile.isLowIncome || profile.hasBplOrAay)) {
            score = 1.0;
            reasonEn = 'You qualify as a woman residing in Odisha aged ${profile.age} (criteria: 21-60 years) for ₹10,000/year DBT under Subhadra Yojana.';
            reasonHi = 'ଆପଣ ଓଡ଼ିଶାରେ ୨୧-୬୦ ବର୍ଷ ବୟସ୍କା ମହିଳା ଭାବରେ ସୁଭଦ୍ରା ଯୋଜନାରେ ବାର୍ଷିକ ₹୧୦,୦୦୦ ଡିବିଟି ସହାୟତା ପାଇଁ ଯୋଗ୍ୟ।';
          }
          break;

        case 'ts_mahalakshmi':
          if (profile.state == 'Telangana' && profile.gender == 'Female' && profile.age >= 18 && (profile.isLowIncome || profile.hasBplOrAay)) {
            score = 1.0;
            reasonEn = 'You qualify as an adult woman residing in Telangana for ₹2,500/month DBT, free TSRTC bus travel, and ₹500 gas cylinder under Mahalakshmi Scheme.';
            reasonHi = 'మీరు మహాలక్ష్మి పథకం కింద నెలకు ₹2,500 డీబీటీ, ఉచిత బస్సు ప్రయాణం మరియు ₹500 గ్యాస్ సిలిండర్ పొందేందుకు అర్హులు.';
          }
          break;

        case 'cg_mahtari_vandan':
          if (profile.state == 'Chhattisgarh' && profile.gender == 'Female' && profile.age >= 21 && profile.age <= 60 && (profile.isLowIncome || profile.hasBplOrAay)) {
            score = 1.0;
            reasonEn = 'You qualify as a married woman aged ${profile.age} in Chhattisgarh for ₹1,000/month (₹12,000/year) DBT under Mahtari Vandan Yojana.';
            reasonHi = 'आप छत्तीसगढ़ की 21-60 वर्ष की महिला के रूप में महतारी वंदन योजना के तहत ₹1,000 प्रतिमाह डीबीटी के पात्र हैं।';
          }
          break;

        case 'dl_mahila_samman':
          if ((profile.state == 'Delhi' || profile.state == 'Delhi (NCT)') && profile.gender == 'Female' && profile.age >= 18 && profile.occupation != 'Salaried') {
            score = 1.0;
            reasonEn = 'You qualify as an adult resident woman in Delhi aged ${profile.age} for ₹1,000/month DBT under Mukhyamantri Mahila Samman Yojana.';
            reasonHi = 'आप दिल्ली की 18+ वर्ष की महिला निवासी के रूप में मुख्यमंत्री महिला सम्मान योजना अंतर्गत ₹1,000 प्रतिमाह के पात्र हैं।';
          }
          break;

        case 'as_orunodoi':
          if (profile.state == 'Assam' && profile.gender == 'Female' && profile.age >= 18 && (profile.isLowIncome || profile.hasBplOrAay)) {
            score = 1.0;
            reasonEn = 'You qualify as a female resident in Assam for ₹1,250/month DBT under Orunodoi 3.0 Scheme.';
            reasonHi = 'অসমৰ স্থায়ী মহিলা বাসিন্দা হিচাপে আপুনি অৰুণোদয় ৩.০ আঁচনিৰ মাহিলী ₹১,২৫০ সাহায্যৰ বাবে যোগ্য।';
          }
          break;

        case 'ka_yuva_nidhi':
          if (profile.state == 'Karnataka' && profile.age >= 21 && profile.age <= 30 && profile.occupation != 'Salaried') {
            score = 1.0;
            reasonEn = 'You qualify as an unemployed degree/diploma holder in Karnataka aged ${profile.age} for ₹1,500 - ₹3,000/month allowance under Yuva Nidhi.';
            reasonHi = 'ನೀವು ಕರ್ನಾಟಕದಲ್ಲಿ ಯುವ ನಿಧಿ ಅಡಿಯಲ್ಲಿ ತಿಂಗಳಿಗೆ ₹೧,೫೦೦ ರಿಂದ ₹೩,೦೦೦ ನಿರುದ್ಯೋಗ ಭತ್ಯೆಗೆ ಅರ್ಹರಾಗಿದ್ದೀರಿ.';
          }
          break;

        case 'mh_yuva_karyaprashikshan':
          if (profile.state == 'Maharashtra' && profile.age >= 18 && profile.age <= 35 && (profile.isStudent || profile.occupation != 'Salaried')) {
            score = 1.0;
            reasonEn = 'You qualify as an educated youth in Maharashtra aged ${profile.age} for ₹6,000 - ₹10,000/month internship stipend under Yuva Karya Prashikshan Yojana.';
            reasonHi = 'तुम्ही महाराष्ट्रातील तरुण म्हणून युवा कार्य प्रशिक्षण योजनेंतर्गत दरमहा ₹६,००० ते ₹१०,००० विद्यावेतनासाठी पात्र आहात.';
          }
          break;

        case 'tn_magalir_urimai':
          if (profile.state == 'Tamil Nadu' && profile.gender == 'Female' && profile.age >= 21 && (profile.isLowIncome || profile.hasBplOrAay)) {
            score = 1.0;
            reasonEn = 'You qualify as a woman family head in Tamil Nadu for ₹1,000/month basic income grant.';
            reasonHi = 'நீங்கள் தமிழ்நாட்டில் மாதம் ₹1,000 மகளிர் உரிமைத் தொகை பெற தகுதியுடையவர்.';
          }
          break;

        case 'ka_gruha_lakshmi':
          if (profile.state == 'Karnataka' && profile.gender == 'Female' && profile.age >= 21 && (profile.hasBplOrAay || profile.isLowIncome)) {
            score = 1.0;
            reasonEn = 'You qualify as the female head of household in Karnataka for ₹2,000/month direct cash assistance.';
            reasonHi = 'ನೀವು ಕರ್ನಾಟಕದಲ್ಲಿ ತಿಂಗಳಿಗೆ ₹೨,೦೦೦ ಗೃಹ ಲಕ್ಷ್ಮಿ ನಗದು ನೆರವಿಗೆ ಅರ್ಹರಾಗಿದ್ದೀರಿ.';
          }
          break;

        case 'or_kalia':
          if (profile.state == 'Odisha' && (profile.isFarmer || profile.occupation == 'Daily Wage / Laborer')) {
            score = 1.0;
            reasonEn = 'You qualify as a farmer or landless agricultural laborer in Odisha for ₹10,000 - ₹12,500 livelihood assistance.';
            reasonHi = 'ଆପଣ ଓଡ଼ିଶାରେ ଚାଷୀ ବା କୃଷି ଶ୍ରମିକ ଭାବରେ କାଳିଆ ଯୋଜନାର ଆର୍ଥିକ ସହାୟତା ପାଇଁ ଯୋଗ୍ୟ।';
          }
          break;

        case 'pb_ashirwad':
          if (profile.state == 'Punjab' && (profile.socialCategory == 'SC' || profile.socialCategory == 'OBC' || profile.hasBplOrAay) && (profile.hasGirlChildUnder10 || (profile.gender == 'Female' && profile.age >= 18))) {
            score = 1.0;
            reasonEn = 'You qualify in Punjab for ₹51,000 financial grant for daughter\'s marriage under the Ashirwad Scheme.';
            reasonHi = 'ਤੁਸੀਂ ਪੰਜਾਬ ਵਿੱਚ ਧੀ ਦੇ ਵਿਆਹ ਲਈ ₹51,000 ਦੀ ਅਸ਼ੀਰਵਾਦ ਸਹਾਇਤਾ ਲਈ ਯੋਗ ਹੋ।';
          }
          break;

        case 'dl_vidyarthi_pratibha':
          if ((profile.state == 'Delhi' || profile.state == 'Delhi (NCT)') && profile.isStudent && (profile.socialCategory != 'General' || profile.isLowIncome)) {
            score = 1.0;
            reasonEn = 'You qualify as a student in Delhi for ₹5,000 - ₹10,000 annual merit scholarship under Vidyarthi Pratibha Yojna.';
            reasonHi = 'आप दिल्ली के छात्र के रूप में ₹5,000 से ₹10,000 वार्षिक विद्यार्थी प्रतिभा छात्रवृत्ति के पात्र हैं।';
          }
          break;

        default:
          // Immediately filter out expired / superseded schemes from active results
          if (scheme.isExpired || scheme.applicationStatus.contains('Expired')) {
            score = 0.0;
            break;
          }

          // Strict occupation and beneficiary criteria alignment
          final isFarmingScheme = scheme.category.toLowerCase().contains('agriculture') ||
              scheme.category.toLowerCase().contains('farmer') ||
              scheme.name.toLowerCase().contains('kisan') ||
              scheme.name.toLowerCase().contains('farmer') ||
              scheme.id.contains('kisan') ||
              scheme.id.contains('farmer') ||
              scheme.summary.toLowerCase().contains('farmer families') ||
              scheme.defaultPlainReason.toLowerCase().contains('farming') ||
              scheme.defaultPlainReason.toLowerCase().contains('farmer');

          if (isFarmingScheme && !profile.isFarmer) {
            // Non-farmers (e.g. Salaried, Student, Artisan, Citizen, etc.) are strictly NOT eligible for farming schemes
            score = 0.0;
            break;
          }

          final isStudentScheme = scheme.category.toLowerCase().contains('scholarship') ||
              scheme.category.toLowerCase().contains('education') ||
              scheme.name.toLowerCase().contains('scholarship') ||
              scheme.name.toLowerCase().contains('fellowship') ||
              scheme.id.contains('scholarship') ||
              scheme.id.contains('fellowship') ||
              scheme.id.contains('vidyarthi');

          if (isStudentScheme && !profile.isStudent) {
            score = 0.0;
            break;
          }

          final isArtisanScheme = scheme.category.toLowerCase().contains('artisan') ||
              scheme.category.toLowerCase().contains('handicraft') ||
              scheme.name.toLowerCase().contains('vishwakarma') ||
              scheme.id.contains('vishwakarma');

          if (isArtisanScheme && !profile.isArtisan) {
            score = 0.0;
            break;
          }

          final isStreetVendorScheme = scheme.id.contains('svanidhi') ||
              scheme.name.toLowerCase().contains('svanidhi') ||
              scheme.name.toLowerCase().contains('street vendor');

          if (isStreetVendorScheme && !profile.isStreetVendor) {
            score = 0.0;
            break;
          }

          final isDisabilityScheme = scheme.category.toLowerCase().contains('disability') ||
              scheme.category.toLowerCase().contains('divyangjan') ||
              scheme.name.toLowerCase().contains('divyang') ||
              scheme.id.contains('disability');

          if (isDisabilityScheme && profile.disabilityStatus == 'None') {
            score = 0.0;
            break;
          }

          if (profile.isSalaried) {
            // Salaried employees are not eligible for unorganized sector relief, agricultural doles, or unemployment assistance
            final isUnemploymentOrDailyWage = scheme.category.toLowerCase().contains('unemployment') ||
                scheme.id.contains('yuva_sathi') ||
                scheme.id.contains('yuva_nidhi') ||
                scheme.id.contains('yuva_shakti') ||
                scheme.id.contains('mgnrega');
            if (isUnemploymentOrDailyWage) {
              score = 0.0;
              break;
            }
          }

          // Check age eligibility if minAge / maxAge defined
          if (!scheme.isAgeEligible(profile.age)) {
            score = 0.0;
            break;
          }

          // Dynamic evaluation for all 28 Indian States & 8 Union Territories
          final isStateMatch = profile.state == 'All India' ||
              scheme.stateScope.toLowerCase().trim() == profile.state.toLowerCase().trim();
          final isApplicableRegion = scheme.isCentral || scheme.stateScope == 'All' || profile.state == 'All India' || isStateMatch;

          if (!isApplicableRegion) {
            score = 0.0;
            break;
          }

          // Check gender eligibility
          if (scheme.genderEligibility != 'All' &&
              scheme.genderEligibility.toLowerCase().trim() != profile.gender.toLowerCase().trim()) {
            score = 0.0;
            break;
          }

          // Check income ceiling
          if (scheme.incomeCeiling == '< 1 Lakh' && !profile.isLowIncome && !profile.hasBplOrAay) {
            score = 0.0;
            break;
          } else if (scheme.incomeCeiling == '< 2.5 Lakh' &&
              (profile.annualIncomeRange == '> 5 Lakh' || profile.annualIncomeRange == '2.5 - 5 Lakh') &&
              !profile.hasBplOrAay) {
            score = 0.0;
            break;
          }

          // Check education / occupation alignment
          if (scheme.educationLevel != 'All' && !profile.isStudent && profile.age > 30) {
            score = 0.3; // Low priority if scheme is academic and user is not student
            break;
          }

          // Matched successfully
          if (isStateMatch && profile.state != 'All India') {
            score = 0.95;
            reasonEn = 'You qualify as a resident of ${profile.state} for this flagship state entitlement (${scheme.category}).';
            reasonHi = 'आप ${profile.state} के निवासी के रूप में इस राज्य स्तरीय योजना (${scheme.category}) के पात्र हैं।';
          } else if (scheme.isCentral) {
            score = 0.85;
            reasonEn = scheme.defaultPlainReason;
            reasonHi = scheme.defaultPlainReasonHi;
          } else {
            score = 0.75;
            reasonEn = 'Flagship state welfare scheme under ${scheme.stateScope} jurisdiction.';
            reasonHi = '${scheme.stateScope} सरकार द्वारा संचालित प्रमुख कल्याणकारी योजना।';
          }
      }

      if (score >= 0.5) {
        scheme.matchConfidence = score;
        scheme.generatedReason = reasonEn.isNotEmpty ? reasonEn : scheme.defaultPlainReason;
        scheme.generatedReasonHi = reasonHi.isNotEmpty ? reasonHi : scheme.defaultPlainReasonHi;
        results.add(scheme);
      }
    }

    // Sort by match score (highest first), then by category
    results.sort((a, b) => b.matchConfidence.compareTo(a.matchConfidence));
    return results;
  }

  // Dynamic question pruning helpers
  static bool shouldAskLandHolding(String occupation) => occupation == 'Farmer';
  static bool shouldAskArtisanTrade(String occupation) => occupation == 'Artisan / Craftsman';
  static bool shouldAskStudentLevel(String occupation) => occupation == 'Student';
  static bool shouldAskWidowStatus(String gender, int age) => gender == 'Female' && age >= 18;
}
