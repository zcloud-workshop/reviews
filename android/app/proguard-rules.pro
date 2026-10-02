# Apache POI references optional SVG rendering classes that are not used by text extraction.
-dontwarn org.apache.batik.**

# Optional desktop graphics, StAX and Saxon classes referenced by Apache POI.
# Reviews only uses Word text extraction, so these code paths are not used on Android.
-dontwarn java.awt.**
-dontwarn javax.xml.stream.**
-dontwarn net.sf.saxon.**
