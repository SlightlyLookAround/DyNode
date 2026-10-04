precision highp float;

//                  CIRCLE:                          SEGMENT:
//in_Position:      XY, type                         XY, type
//in_Normal:        Radius X, radius Y               Circle XY, radius
//in_Colour1:       Outer fill RGBA                  Outer fill RGBA
//in_Colour2:       Inner fill RGB                   Wedge centre, wedge size, unused
//in_Colour3:       Border colour                    Border colour
//in_TextureCoord:  Inner fill A, border thickness   Unused, border thickness
//
//                  RING:                            RECTANGLE:                
//in_Position:      XY, type                         XY, type                  
//in_Normal:        Shape XY, radius                 Unused      
//in_Colour1:       Fill RGBA                        Fill colour               
//in_Colour2:       Radius, angle, angle             Rect WH, unused           
//in_Colour3:       Border colour                    Border colour             
//in_TextureCoord:  Unused, border thickness         Rounding, border thickness
//
//                  LINE:                            CONVEX:
//in_Position:      XY, type                         XY, type
//in_Normal:        x1, y1, unused                   First boundary
//in_Colour1:       Fill colour                      Fill colour
//in_Colour2:       x2, y2, unused                   Second boundary
//in_Colour3:       Unused                           Border colour
//in_TextureCoord:  Thickness, unused                Rounding, border thickness
//
//                  POLYLINE:                        N-GON:
//in_Position:      XY, type                         XY, type
//in_Normal:        x1, y1, x3                       Centre XY, radius
//in_Colour1:       Fill colour                      Fill RGBA
//in_Colour2:       x2. y2, y3                       Sides, star factor, rotation
//in_Colour3:       Unused                           Border colour
//in_TextureCoord:  Thickness, unused                Rounding, border thickness



attribute vec3 in_Position;
attribute vec3 in_Normal;
attribute vec4 in_Colour1;
attribute vec3 in_Colour2;
attribute vec4 in_Colour3;
attribute vec2 in_TextureCoord;



//Shared
varying vec4 v_packed0;
varying vec4 v_packed1;
varying vec4 v_packed2;
varying vec4 v_packed3;
varying vec4 v_packed4;
varying vec4 v_packed5;
varying vec4 v_packed6;
varying vec4 v_packed7;
varying vec4 v_packed8;
varying vec4 v_packed9;
varying vec4 v_packed10;
varying vec4 v_packed11;
varying vec4 v_packed12;
varying vec4 v_packed13;
varying vec4 v_packed14;
// [GMRT-WA-15767] 上面这些数据被打包进少量 vec4：WebGPU 的顶点输出上限是 16 个，
// 原来的 ~30 个 varying 会让 Clean 的 pipeline 创建失败（黑屏 + 每帧校验报错）。
// 数据本身没变，只是换了存放方式；GMS2/YYC 同样适用。
#define v_vFillColour v_packed0
#define v_vBorderColour v_packed1
#define v_vCircleInnerColour v_packed2
#define v_vLine1 v_packed3.xyz
#define v_vLine2 v_packed4.xyz
#define v_vNgonXYR v_packed5.xyz
#define v_vSegmentXYR v_packed6.xyz
#define v_vPosition v_packed7.xy
#define v_vCircleRadius v_packed7.zw
#define v_vCircleCoord v_packed8.xy
#define v_vRectangleXY v_packed8.zw
#define v_vRectangleWH v_packed9.xy
#define v_vLineA v_packed9.zw
#define v_vLineB v_packed10.xy
#define v_vLineC v_packed10.zw
#define v_vRingCentre v_packed11.xy
#define v_vOutputTexel v_packed11.zw
#define v_fMode v_packed3.w
#define v_fBorderThickness v_packed4.w
#define v_fRounding v_packed5.w
#define v_fLineThickness v_packed6.w
#define v_fNgonSides v_packed12.x
#define v_fNgonStarFactor v_packed12.y
#define v_fNgonAngle v_packed12.z
#define v_vSegmentApertureCentre v_packed12.w
#define v_vSegmentApertureSize v_packed13.x
#define v_fRingApertureCentre v_packed13.y
#define v_fRingApertureSize v_packed13.z
#define v_fRingInnerRadius v_packed13.w
#define v_fRingOuterRadius v_packed14.x
#define v_fBorder v_packed14.y

//Circle

//Rectangle

//Line + Polyline

//Convex

//N-gon

//Segment

//Ring



void main()
{
    gl_Position = gm_Matrices[MATRIX_WORLD_VIEW_PROJECTION]*vec4(in_Position.xy, 0.0, 1.0);
    
    //Shared
    v_vPosition        = in_Position.xy;
    v_fMode            = in_Position.z;
    v_vFillColour      = in_Colour1;
    v_vBorderColour    = in_Colour3;
    v_fRounding        = in_TextureCoord.x;
    v_fBorderThickness = in_TextureCoord.y;
    
    //Extract flags
    float flagA = 0.0;
    float flagB = 0.0;
    if (v_fMode >= 131072.0) { v_fMode -= 131072.0; flagB = 1.0; } // 2^17
    if (v_fMode >=  65536.0) { v_fMode -=  65536.0; flagA = 1.0; } // 2^16
    
    //Shapes with borders
    //TODO - Reorganise or use a flag
    v_fBorder = float(v_fMode == 3.0 || v_fMode == 4.0 || v_fMode == 5.0 || v_fMode == 7.0 || v_fMode == 8.0 || v_fMode == 9.0);
    
    //Circle
    v_vCircleRadius      = in_Normal.xy;
    v_vCircleCoord       = 2.0*v_vCircleRadius*(vec2(flagA, flagB) - 0.5);
    v_vCircleInnerColour = vec4(in_Colour2, in_TextureCoord.x);
    
    //Rectangle
    v_vRectangleWH = in_Colour2.xy;
    v_vRectangleXY = v_vPosition + v_vRectangleWH*(0.5 - vec2(flagA, flagB));
    
    //Line + Polyline
    v_vLineA         = in_Normal.xy;
    v_vLineB         = in_Colour2.xy;
    v_vLineC         = vec2(in_Normal.z, in_Colour2.z);
    v_fLineThickness = in_TextureCoord.x;
    
    //Polygon
    v_vLine1 = in_Normal;
    v_vLine2 = in_Colour2;
    
    //N-gon
    v_vNgonXYR        = in_Normal;
    v_fNgonSides      = in_Colour2.x;
    v_fNgonStarFactor = in_Colour2.y;
    v_fNgonAngle      = in_Colour2.z;
    
    //Segment
    v_vSegmentXYR             = in_Normal;
    v_vSegmentApertureCentre = in_Colour2.x;
    v_vSegmentApertureSize   = in_Colour2.y;
    
    //Ring
    v_vRingCentre         = in_Normal.xy;
    v_fRingApertureCentre = in_Colour2.y;
    v_fRingApertureSize   = in_Colour2.z;
    v_fRingInnerRadius    = in_Normal.z;
    v_fRingOuterRadius    = in_Colour2.x;
}
