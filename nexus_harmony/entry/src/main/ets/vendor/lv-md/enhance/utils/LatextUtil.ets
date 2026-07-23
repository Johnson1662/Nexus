import { LatexMathColorFormat, latexStringToImage } from '@cangjie-tpc/formula_hybrid';
import { image } from '@kit.ImageKit';
import { common } from '@kit.AbilityKit';

export interface LatexInfo {
  pixelMap: image.PixelMap,
  width: number
  height: number
}

export namespace LatexUtil {
  // 缓存数学公式图片，键为公式文本、字体大小和颜色的组合
  const latexCache: Map<string, LatexInfo> = new Map();

  function buildCacheKey(latexText: string, latexMathTextSize: number, latexMathTextColor: number): string {
    return `${latexText}_${latexMathTextSize}_${latexMathTextColor}`;
  }

  export function latexToPixelMap(latexText: string, latexMathTextSize: number,
    latexMathTextColor: number, context: UIContext): Promise<LatexInfo> {
    // 生成缓存键
    const cacheKey = buildCacheKey(latexText, latexMathTextSize, latexMathTextColor);

    // 检查缓存中是否已有该公式的图片
    if (latexCache.has(cacheKey)) {
      return Promise.resolve(latexCache.get(cacheKey)!);
    }

    let abilityStageContext = getContext() as common.AbilityStageContext;
    // 获取当前模块名
    let moduleName = abilityStageContext.currentHapModuleInfo.name;

    // 缓存中没有，生成新的图片
    return new Promise(async (resolve, reject) => {
      try {
        let buf: ArrayBuffer =
          await latexStringToImage(latexText, context.fp2px(latexMathTextSize), latexMathTextColor, 0x00000000,
            LatexMathColorFormat.COLOR_FORMAT_BGRA_8888, `/data/storage/el1/bundle/${moduleName}/resources/resfile/res`)
        let imageSource = image.createImageSource(buf)
        // 图片pixelMap
        let pixelMap = imageSource.createPixelMapSync()
        let size: Size = pixelMap.getImageInfoSync().size

        const latexInfo: LatexInfo = {
          pixelMap: pixelMap,
          width: size.width,
          height: size.height
        };

        // 将生成的图片存入缓存
        latexCache.set(cacheKey, latexInfo);

        resolve(latexInfo);
      } catch (err) {
        reject(err);
      }
    });
  }

  export function getCachedLatex(latexText: string, latexMathTextSize: number,
    latexMathTextColor: number): LatexInfo | undefined {
    return latexCache.get(buildCacheKey(latexText, latexMathTextSize, latexMathTextColor));
  }

  // 清理缓存，当整个Markdown组件销毁时调用
  export function clearCache() {
    latexCache.clear();
  }
}
